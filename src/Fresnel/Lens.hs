module Fresnel.Lens
( -- * Lenses
  Lens
, Lens'
  -- * Construction
, lens
  -- * Tuples
, fst_
) where

import Control.Arrow ((&&&))
import Data.Profunctor
import Fresnel.Optic

-- Lenses

type Lens s t a b = forall p . Strong p => Optic p s t a b

type Lens' s a = Lens s s a a


-- Construction

lens :: (s -> a) -> (s -> b -> t) -> Lens s t a b
lens get set = dimap (get &&& id) (uncurry (flip set)) . first'


-- Tuples

fst_ :: Lens (a, b) (a', b) a a'
fst_ = lens fst (\ s a' -> (a', snd s))
