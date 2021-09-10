{-# LANGUAGE GeneralisedNewtypeDeriving #-}
{-# LANGUAGE RankNTypes #-}
module Fresnel.Fold
( -- * Folds
  Fold
, IsFold
  -- * Construction
, folded
, unfolded
, folding
, foldring
  -- * Elimination
, foldMapOf
, foldrOf
, foldOf
, traverseOf_
, previews
, preview
, (^?)
, Union(..)
) where

import Data.Foldable (traverse_)
import Data.Functor.Contravariant
import Data.Monoid
import Data.Profunctor
import Data.Profunctor.Traversing
import Data.Profunctor.Unsafe ((#.), (.#))
import Fresnel.Bifunctor.Contravariant
import Fresnel.Functor.Traversed
import Fresnel.Monoid.Cons as Cons
import Fresnel.Optic
import Fresnel.OptionalFold.Internal (IsOptionalFold)
import Fresnel.Traversal (IsTraversal)

-- Folds

type Fold s a = forall p . IsFold p => Optic' p s a

class (IsOptionalFold p, IsTraversal p) => IsFold p

instance Monoid r => IsFold (Forget r)
instance (Applicative f, Traversable f, Contravariant f) => IsFold (Star f)


-- Construction

folded :: Foldable f => Fold (f a) a
folded = rphantom . wander traverse_

unfolded :: (s -> Maybe (a, s)) -> Fold s a
unfolded coalg = rphantom . wander (\ f -> let loop = maybe (pure ()) (\ (a, s) -> f a *> loop s) . coalg in loop)

folding :: Foldable f => (s -> f a) -> Fold s a
folding f = contrabimap f (const ()) . rmap (const ()) . wander traverse_

foldring :: (forall f . Applicative f => (a -> f u -> f u) -> f v -> s -> f w) -> Fold s a
foldring fr = rphantom . wander (\ f -> fr (\ a -> (f a *>)) (pure v)) where
  v = error "foldring: value used"


-- Elimination

foldMapOf :: Monoid m => Fold s a -> ((a -> m) -> (s -> m))
foldMapOf o = runForget #. o .# Forget

foldrOf :: Fold s a -> ((a -> r -> r) -> r -> s -> r)
foldrOf o cons nil s = runCons (runForget (o (Forget Cons.cons)) s) cons nil

foldOf :: Monoid a => Fold s a -> (s -> a)
foldOf o = foldMapOf o id

traverseOf_ :: Applicative f => Fold s a -> ((a -> f r) -> (s -> f ()))
traverseOf_ o f = runTraversed . foldMapOf o (Traversed #. f)


previews :: Fold s a -> (a -> r) -> (s -> Maybe r)
previews o f = getFirst #. foldMapOf o (First #. Just . f)

preview :: Fold s a -> s -> Maybe a
preview o = previews o id

(^?) :: s -> Fold s a -> Maybe a
s ^? l = getFirst (foldMapOf l (First #. Just) s)

infixl 8 ^?


newtype Union s a = Union { getUnion :: Fold s a }

instance Semigroup (Union s a) where
  Union a1 <> Union a2 = Union (rphantom . wander (\ f s -> traverseOf_ a1 f s *> traverseOf_ a2 f s) . rphantom)
