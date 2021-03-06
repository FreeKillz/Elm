module Type.Constrain.Pattern where

import Control.Arrow (second)
import Control.Applicative ((<$>))
import qualified Control.Monad as Monad
import Control.Monad.Error
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified Data.Map as Map

import SourceSyntax.Pattern
import SourceSyntax.PrettyPrint
import Text.PrettyPrint (render)
import qualified SourceSyntax.Location as Loc
import Type.Type
import Type.Fragment
import Type.Environment as Env
import qualified Type.Constrain.Literal as Literal


constrain :: Environment -> Pattern -> Type -> ErrorT String IO Fragment
constrain env pattern tipe =
    let span = Loc.NoSpan (render $ pretty pattern)
        t1 === t2 = Loc.L span (CEqual t1 t2)
        x <? t = Loc.L span (CInstance x t)
    in
    case pattern of
      PAnything -> return emptyFragment

      PLiteral lit -> do
          c <- liftIO $ Literal.constrain env span lit tipe
          return $ emptyFragment { typeConstraint = c }

      PVar name -> do
          v <- liftIO $ var Flexible
          return $ Fragment {
              typeEnv    = Map.singleton name (VarN v),
              vars       = [v],
              typeConstraint = VarN v === tipe
          }

      PAlias name p -> do
          fragment <- constrain env p tipe
          return $ fragment {
              typeEnv = Map.insert name tipe (typeEnv fragment),
              typeConstraint = name <? tipe /\ typeConstraint fragment
            }

      PData name patterns -> do
          (kind, cvars, args, result) <- liftIO $ freshDataScheme env name
          let msg = concat [ "Constructor '", name, "' expects ", show kind
                           , " argument", if kind == 1 then "" else "s"
                           , " but was given ", show (length patterns), "." ]
          if length patterns /= kind then throwError msg else do
              fragment <- Monad.liftM joinFragments (Monad.zipWithM (constrain env) patterns args)
              return $ fragment {
                typeConstraint = typeConstraint fragment /\ tipe === result,
                vars = cvars ++ vars fragment
              }

      PRecord fields -> do
          pairs <- liftIO $ mapM (\name -> (,) name <$> var Flexible) fields
          let tenv = Map.fromList (map (second VarN) pairs)
          c <- liftIO . exists $ \t -> return (tipe === record (Map.map (:[]) tenv) t)
          return $ Fragment {
              typeEnv        = tenv,
              vars           = map snd pairs,
              typeConstraint = c
          }
