{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
module Main
( main
) where

import Data.Foldable (for_)
import Text.Blaze.Svg.Renderer.Pretty
import Text.Blaze.Svg11 as S
import Text.Blaze.Svg11.Attributes as A

main :: IO ()
main = putStrLn . renderSvg $ svg ! version "1.1" ! xmlns "http://www.w3.org/2000/svg" ! viewbox "-575 -50 1300 650" $ do
  S.style (toMarkup ("@import url(https://cdn.rawgit.com/dreampulse/computer-modern-web-font/master/fonts.css);" :: String))
  case out graph of
    Mu ns f -> do
      for_ (f ns) $ \ Vertex{ kind, name, point, edges } -> do
        g ! id_ (stringValue name) ! A.class_ (stringValue ("vertex " <> show kind)) $ do
          for_ edges $ \ dest -> S.path ! id_ (stringValue (name <> "-" <> dest))
          text_ (toMarkup name)

xmlns = customAttribute "xmlns"

newtype Graph = In { out :: forall v . Mu v }

data Mu v = Mu [String] ([v] -> [Vertex v])

data Vertex v = Vertex { kind :: VertexKind, name :: String, point :: Point Int, edges :: [v] }

data VertexKind
  = Optic
  | Class
  deriving (Eq, Ord, Show)

data Point a = Point
  { x :: a
  , y :: a
  , z :: a
  }
  deriving (Functor)

graph :: Graph
graph = In $ Mu ["Iso", "Lens", "Getter", "Prism", "Review", "Optional", "AffineFold", "Traversal", "Fold", "Setter", "Profunctor", "Strong", "Cochoice", "Bicontravariant", "Choice", "Costrong", "Bifunctor", "Closed", "Traversing", "Mapping"] $ \case
  [iso, lens, getter, prism, review, optional, affineFold, traversal, fold, setter, _profunctor, strong, cochoice, _bicontravariant, choice, costrong, _bifunctor, closed, traversing, mapping] ->
    [ Vertex Optic "Iso" (Point 0 0 0) [lens, prism]
    , Vertex Optic "Lens" (Point 1 0 0) [optional, getter]
    , Vertex Optic "Getter" (Point 2 0 0) [affineFold]
    , Vertex Optic "Prism" (Point 0 1 0) [optional, review]
    , Vertex Optic "Review" (Point 0 2 0) []
    , Vertex Optic "Optional" (Point 1 1 0) [affineFold, traversal]
    , Vertex Optic "AffineFold" (Point 2 1 0) [fold]
    , Vertex Optic "Traversal" (Point 1 2 0) [fold, setter]
    , Vertex Optic "Fold" (Point 2 2 0) []
    , Vertex Optic "Setter" (Point 1 3 0) []
    , Vertex Class "Profunctor" (Point 0 0 1) [iso, strong, choice, cochoice, costrong, closed]
    , Vertex Class "Strong" (Point 1 0 1) [lens, traversing]
    , Vertex Class "Cochoice" (Point 2 0 1) [getter]
    , Vertex Class "Bicontravariant" (Point 2 0 2) [getter]
    , Vertex Class "Choice" (Point 0 1 1) [prism, traversing]
    , Vertex Class "Costrong" (Point 0 2 1) [review]
    , Vertex Class "Bifunctor" (Point 0 2 2) [review]
    , Vertex Class "Closed" (Point 0 3 1) [mapping]
    , Vertex Class "Traversing" (Point 0 3 1) [traversal, mapping]
    , Vertex Class "Mapping" (Point 0 3 1) [setter]
    ]
  _ -> error "not enough vertices, or too many. either way, it’s bad."
