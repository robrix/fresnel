{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
module Main
( main
) where

import           Control.Monad (unless)
import           Data.Bool (bool)
import           Data.Char (isSpace)
import           Data.Colour.RGBSpace
import           Data.Colour.RGBSpace.HSL
import           Data.Colour.SRGB
import           Data.Foldable (toList, traverse_)
import           Data.List (intercalate, intersperse)
import qualified Data.Map as Map
import           Data.Traversable (for)
import qualified Fold.Test
import           GHC.Exception.Type (Exception(displayException))
import qualified Getter.Test
import qualified Iso.Test
import qualified Monoid.Fork.Test
import qualified Profunctor.Coexp.Test
import           System.Console.ANSI
import           System.Exit (exitFailure, exitSuccess)
import           Test.QuickCheck

main :: IO ()
main = traverse (runQuickCheckAll (quickCheckWithResult stdArgs{ maxSuccess = 250, chatty = False }) . uncurry Group . fmap (map (uncurry Case)))
  [ Fold.Test.tests
  , Getter.Test.tests
  , Iso.Test.tests
  , Monoid.Fork.Test.tests
  , Profunctor.Coexp.Test.tests
  ]
  >>= tally . foldr (\ (s, f) (ss, fs) -> (s + ss, f + fs)) (0, 0)
  >>= bool exitFailure exitSuccess . (== 0) . snd

data Group = Group
  { name  :: String
  , cases :: [Case]
  }

data Case = Case
  { name     :: String
  , property :: Property
  }

runQuickCheckAll :: (Property -> IO Result) -> Group -> IO (Int, Int)
runQuickCheckAll qc Group{ name = __FILE__, cases = ps } = do
  withSGR [setBold, setRGB (hsl 300 1 0.75)] $
    putStrLn __FILE__
  putStrLn ""
  rs <- for ps $ \ Case{ name = xs, property = p } -> do
    loc <- case breaks [isSpace, not . isSpace, isSpace, not . isSpace] xs of
      [propName, _, _, _, loc] -> do
        withSGR [setBold] $
          putStrLn (unwords (filter (\ s -> s /= "_" && s /= "prop") (breakAll (== '_') propName)))
        pure (Just loc)
      _ -> pure Nothing
    r <- qc p
    result loc r
    putStrLn ""
    pure (isSuccess r)

  tally (length (filter id rs), length (filter not rs))

result :: Maybe String -> Result -> IO ()
result loc = \case
  Success{ numTests, numDiscarded, labels, classes, tables } -> do
    success $ putStr "OK "
    parens $ stats $ emptyStats{ Main.numTests, Main.numDiscarded, Main.labels, Main.classes, Main.tables }
    putStrLn ""
  GaveUp{ numTests, numDiscarded, labels, classes, tables } -> do
    failure $ putStr "FAIL "
    parens $ stats $ emptyStats{ Main.numTests, Main.numDiscarded, Main.labels, Main.classes, Main.tables }
    putStrLn ""
  Failure{ numTests, numDiscarded, numShrinks, usedSeed, usedSize, reason, theException, failingTestCase, failingLabels, failingClasses } -> do
    maybe (pure ()) putStrLn loc
    failure $ putStr "FAIL "
    parens $ stats $ emptyStats{ Main.numTests, Main.numDiscarded, Main.numShrinks }
    putStrLn ":"
    putStrLn ""
    putStrLn reason
    maybe (pure ()) (putStrLn . displayException) theException
    traverse_ putStrLn failingTestCase
    putStrLn ""
    putStrLn ("Seed: " ++ show usedSeed)
    putStrLn ("Size: " ++ show usedSize)
    unless (null failingLabels) $ putStrLn ("Labels: " ++ intercalate ", " failingLabels)
    unless (null failingClasses) $ putStrLn ("Classes: " ++ intercalate ", " (toList failingClasses))
  NoExpectedFailure{ numTests, numDiscarded, labels, classes, tables } -> do
    failure $ putStr "FAIL "
    parens $ stats $ emptyStats{ Main.numTests, Main.numDiscarded, Main.labels, Main.classes, Main.tables }
    putStrLn ""

data Stats = Stats
  { numTests     :: Int
  , numDiscarded :: Int
  , numShrinks   :: Int
  , labels       :: Map.Map [String] Int
  , classes      :: Map.Map String Int
  , tables       :: Map.Map String (Map.Map String Int)
  }

emptyStats :: Stats
emptyStats = Stats
  { numTests       = 0
  , numDiscarded   = 0
  , numShrinks     = 0
  , labels         = Map.empty
  , classes        = Map.empty
  , tables         = Map.empty
  }

stats :: Stats -> IO ()
stats Stats{ numTests, numDiscarded, numShrinks } = do
  sequence_ . intersperse (putStr ", ")
    $  toList (stat (S "test") numTests)
    ++ toList (stat (S "discard") numDiscarded)
    ++ toList (stat (S "shrink") numShrinks)

data Plural
  = S String
  | C String String

pluralize :: Int -> Plural -> String
pluralize 1 = \case
  S s   -> s
  C s _ -> s
pluralize _ = \case
  S   s -> s ++ "s"
  C _ s -> s

stat :: Plural -> Int -> Maybe (IO ())
stat _    0 = Nothing
stat name n = Just $ do
  putStr (show n)
  putStr " "
  putStr (pluralize n name)

tally :: (Int, Int) -> IO (Int, Int)
tally (successes, failures) = do
  let hasSuccesses = successes /= 0
      hasFailures = failures /= 0
  if hasFailures then
    failure $ putStr "Failed:"
  else
    success $ putStr "Succeeded:"
  putStr " "
  if hasSuccesses then
    success $ do
      putStr (show successes)
      putStr (if successes == 1 then " success"  else" successes")
  else
    putStr "0 successes"
  putStr ", "
  if hasFailures then
    failure $ do
      putStr (show failures)
      putStr (if failures == 1 then " failure" else " failures")
  else
    putStr "0 failures"
  putStrLn ""
  putStrLn ""
  pure (successes, failures)

setRGB :: RGB Float -> SGR
setRGB = SetRGBColor Foreground . uncurryRGB sRGB

setBold :: SGR
setBold = SetConsoleIntensity BoldIntensity


parens :: IO a -> IO a
parens m = do
  putStr "("
  a <- m
  a <$ putStr ")"


red :: RGB Float
red = hsl 0 1 0.5

green :: RGB Float
green = hsl 120 1 0.5


withSGR :: [SGR] -> IO a -> IO a
withSGR sgr io = setSGR sgr *> io <* setSGR []

colour :: RGB Float -> IO a -> IO a
colour c = withSGR [setRGB c]

success, failure :: IO a -> IO a

success = colour green
failure = colour red


breaks :: [a -> Bool] -> [a] -> [[a]]
breaks ps as = case ps of
  []   -> [as]
  p:ps -> let (h, t) = break p as in h : breaks ps t

breakAll :: (a -> Bool) -> [a] -> [[a]]
breakAll p = go False where
  go b = \case
    [] -> []
    as -> let (h, t) = break (if b then not . p else p) as in h : go (not b) t
