{-# LANGUAGE RankNTypes #-}
module Fresnel.Traversal1
( -- * Relevant traversals
  Traversal1
, Traversal1'
, IsTraversal1
  -- * Construction
, traversal1
, traversed1
, backwards
  -- * Elimination
, traverse1Of
, for1Of
) where

import Control.Applicative.Backwards
import Data.Functor.Apply
import Data.Profunctor (Star(..))
import Data.Profunctor.Unsafe ((#.), (.#))
import Data.Semigroup.Traversable
import Fresnel.Optic
import Fresnel.Profunctor.Traversing1
import Fresnel.Traversal1.Internal

-- Relevant traversals

type Traversal1 s t a b = forall p . IsTraversal1 p => Optic p s t a b

type Traversal1' s a = Traversal1 s s a a


-- Construction

traversal1 :: (forall f . Apply f => (a -> f b) -> (s -> f t)) -> Traversal1 s t a b
traversal1 = wander1

traversed1 :: Traversable1 t => Traversal1 (t a) (t b) a b
traversed1 = traversal1 traverse1

-- | Reverse the order in which a (finite) 'Traversal1' is traversed.
--
-- @
-- 'backwards' . 'backwards' = 'id'
-- @
backwards :: Traversal1 s t a b -> Traversal1 s t a b
backwards o = traversal1 (\ f -> forwards #. traverse1Of o (Backwards #. f))


-- Elimination

-- | Map over the targets of an 'Fresnel.Iso.Iso', 'Fresnel.Lens.Lens', 'Fresnel.Optional.Optional', or 'Traversal', collecting the results.
--
-- @
-- 'traverse1Of' . 'traversal1' = 'id'
-- 'traverse1Of' 'traversed1' = 'traverse1'
-- @
traverse1Of :: Apply f => Traversal1 s t a b -> ((a -> f b) -> (s -> f t))
traverse1Of o = runStar #. o .# Star

for1Of :: Apply f => Traversal1 s t a b -> (s -> (a -> f b) -> f t)
for1Of o = flip (traverse1Of o)
