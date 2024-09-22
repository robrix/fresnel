module Fresnel.Fold1.Internal
( IsFold1
) where

import Data.Functor.Apply
import Data.Functor.Contravariant
import Data.Profunctor (Forget, Star)
import Fresnel.Getter.Internal (IsGetter)
import Fresnel.Profunctor.OptionalStar (OptionalStar)
import Fresnel.Traversal1.Internal (IsTraversal1)

class (IsGetter p, IsTraversal1 p) => IsFold1 p

instance Semigroup r => IsFold1 (Forget r)
instance (Contravariant f, Apply f, Traversable f) => IsFold1 (Star f)
instance (Contravariant f, Apply f, Traversable f) => IsFold1 (OptionalStar f)