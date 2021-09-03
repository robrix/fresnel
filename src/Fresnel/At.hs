{-# LANGUAGE RankNTypes #-}
module Fresnel.At
( -- * Updateable collections
  At(..)
  -- * Indexable collections
, module Fresnel.Ixed
) where

import           Control.Monad (guard)
import qualified Data.IntMap as IntMap
import qualified Data.IntSet as IntSet
import           Fresnel.Ixed
import           Fresnel.Lens (Lens', lens)

class Ixed c => At c where
  at :: Index c -> Lens' c (Maybe (IxValue c))

instance At IntSet.IntSet where
  at k = lens (guard . IntSet.member k) (\ s -> maybe s (const (IntSet.insert k s)))

instance At (IntMap.IntMap v) where
  at k = lens (IntMap.lookup k) (\ m -> maybe m (flip (IntMap.insert k) m))
