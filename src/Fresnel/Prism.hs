module Fresnel.Prism
( -- * Prisms
  Prism
, Prism'
  -- * Construction
, prism
) where

import Data.Profunctor
import Fresnel.Optic

-- Prisms

type Prism s t a b = forall p . Choice p => Optic p s t a b

type Prism' s a = Prism s s a a


-- Construction

prism :: (b -> t) -> (s -> Either t a) -> Prism s t a b
prism inj prj = dimap prj (either id inj) . right'
