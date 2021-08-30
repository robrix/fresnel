{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE LambdaCase #-}
module Fresnel.AffineTraversal
( -- * Affine traversals
  AffineTraversal
, AffineTraversing
  -- * Construction
, atraversal
  -- * Unpacked
, UnpackedAffineTraversal(..)
, unpackedAffineTraversal
) where

import Fresnel.Profunctor.Optical
import Fresnel.Optic
import Data.Profunctor

-- Affine traversals

type AffineTraversal s t a b = forall p . AffineTraversing p => Optic p s t a b


-- Construction

atraversal :: (s -> Either t a) -> (s -> b -> t) -> AffineTraversal s t a b
atraversal prj set = dimap
  (\ s -> (prj s, set s))
  (\case
    (Left  t, _) -> t
    (Right b, f) -> f b)
  . first' . right'


-- Unpacked

newtype UnpackedAffineTraversal a b s t = UnpackedAffineTraversal { withUnpackedAffineTraversal :: forall r . ((s -> Either t a) -> (s -> b -> t) -> r) -> r }

unpackedAffineTraversal :: (s -> Either t a) -> (s -> b -> t) -> UnpackedAffineTraversal a b s t
unpackedAffineTraversal prj set = UnpackedAffineTraversal (\ k -> k prj set)
