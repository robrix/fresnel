module Fresnel.Iso
( -- * Isos
  Iso
, Iso'
  -- * Construction
, iso
, from
  -- * Elimination
, withIso
, under
  -- * Functions
, involuted
, flipped
, curried
) where

import Data.Profunctor
import Fresnel.Optic
import Fresnel.Profunctor.Coexp

-- Isos

type Iso s t a b = forall p . Profunctor p => Optic p s t a b

type Iso' s a = Iso s s a a


-- Construction

iso :: (s -> a) -> (b -> t) -> Iso s t a b
iso = dimap

from :: Iso s t a b -> Iso b a t s
from o = withIso o (flip iso)


-- Elimination

withIso :: Iso s t a b -> (((s -> a) -> (b -> t) -> r) -> r)
withIso i = withCoexp (i (Coexp id id)) . flip


under :: Iso s t a b -> (t -> s) -> (b -> a)
under i = withIso i (\ f r -> (f .) . (. r))


-- Functions

involuted :: (a -> a) -> Iso' a a
involuted f = iso f f

flipped :: Iso (a -> b -> c) (a' -> b' -> c') (b -> a -> c) (b' -> a' -> c')
flipped = iso flip flip

curried :: Iso ((a, b) -> c) ((a', b') -> c') (a -> b -> c) (a' -> b' -> c')
curried = iso curry uncurry
