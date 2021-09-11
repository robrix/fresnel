{-# LANGUAGE RankNTypes #-}
module Fresnel.Monoid.Fork
( -- * Binary trees
  Fork(..)
  -- * Construction
, singleton
) where

import Data.Foldable (toList)

-- Binary trees

newtype Fork a = Fork { runFork :: forall r . (r -> r -> r) -> (a -> r) -> r -> r }

instance Show a => Show (Fork a) where
  showsPrec _ = showList . toList

instance Semigroup (Fork a) where
  Fork a1 <> Fork a2 = Fork (\ fork leaf nil -> a1 fork leaf nil `fork` a2 fork leaf nil)

instance Monoid (Fork a) where
  mempty = Fork (\ _ _ nil -> nil)

instance Foldable Fork where
  foldMap f (Fork r) = r (<>) f mempty

instance Functor Fork where
  fmap f (Fork r) = Fork (\ fork leaf -> r fork (leaf . f))


-- Construction

singleton :: a -> Fork a
singleton a = Fork (\ _ leaf _ -> leaf a)
