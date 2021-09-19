{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TupleSections #-}
module Main
( main
) where

import           Control.Applicative (liftA2)
import           Control.Monad (guard, unless, when)
import           Control.Monad.IO.Class
import           Data.Foldable (for_, toList, traverse_)
import qualified Data.IntMap as IntMap
import           Data.List (elemIndex, intercalate, intersperse, sortBy)
import qualified Data.Map as Map
import           Data.Maybe (fromMaybe)
import           Data.Ord (comparing)
import qualified Fold.Test
import           Fresnel.Lens (Lens', lens)
import           Fresnel.Setter
import           GHC.Exception.Type (Exception(displayException))
import qualified Getter.Test
import qualified Iso.Test
import qualified Monoid.Fork.Test
import           Numeric (readDec, showFFloatAlt)
import qualified Profunctor.Coexp.Test
import           System.Console.ANSI
import           System.Console.GetOpt
import           System.Environment (getArgs, getProgName)
import           System.Exit (exitFailure, exitSuccess)
import           System.IO
import           Test.Group
import           Test.QuickCheck (Args(..), Result(Failure, GaveUp, NoExpectedFailure, Success), isSuccess, quickCheckWithResult, stdArgs, (.&&.), (===))
import qualified Test.QuickCheck as QC
import           Test.QuickCheck.Random (QCGen)
import           Test.QuickCheck.Test (Result(failingClasses))

main :: IO ()
main = do
  let opts =
        [ Option "n" ["successes"] (ReqArg (set (args_.maxSuccess_)        . int) "N") "require N successful tests before concluding the property passes"
        , Option "z" ["size"]      (ReqArg (set (args_.maxSize_)           . int) "N") "increase the size parameter to a maximum of N for successive tests of a property"
        , Option "s" ["shrinks"]   (ReqArg (set (args_.maxShrinks_)        . int) "N") "perform a maximum of N shrinks; setting this to 0 disables shrinking"
        , Option "g" ["group"]     (ReqArg (\ s -> groups_ %~ (s:))            "NAME") "include the named group; can be used multiple times to include multiple groups"
        , Option "r" ["replay"]    (ReqArg (set (args_.replay_) . Just . read) "SEED") "the seed and size to repeat"
        ]
  (mods, other, errs) <- getOpt RequireOrder opts <$> getArgs
  case map ("Unrecognized argument: " ++) other ++ errs of
    [] -> pure ()
    _  -> do
      name <- getProgName
      for_ (errs ++ [usageInfo (header name) opts]) (hPutStrLn stderr)
  let Options gs _ args = foldr ($) (Options{ groups = [], cases = [], args = stdArgs{ maxSuccess = 250, chatty = False }}) mods
      matching _ [] = id
      matching f fs = filter (\ g -> foldr ((||) . f g) False fs)
  (t, _) <- runLayout (traverse_ (runGroup args w) (matching ((==) . groupName) gs groups)) (pure ())
  _ <- runLayout (sequence_ (tally t)) (pure ())
  if isFailure t then
    exitFailure
  else
    exitSuccess
  where
  groups =
    [ Fold.Test.tests
    , Getter.Test.tests
    , Iso.Test.tests
    , Monoid.Fork.Test.tests
    , Profunctor.Coexp.Test.tests
    , tropical
    ]
  w = fromMaybe 0 (getTropical (maxWidths groups))
  int = fst . head . readDec
  header name = "Usage: " ++ name ++ " [-n N|--successes N]"

maxSuccess_ :: Lens' Args Int
maxSuccess_ = lens maxSuccess (\ a maxSuccess -> a{ maxSuccess })

maxSize_ :: Lens' Args Int
maxSize_ = lens maxSize (\ a maxSize -> a{ maxSize })

maxShrinks_ :: Lens' Args Int
maxShrinks_ = lens maxShrinks (\ a maxShrinks -> a{ maxShrinks })

replay_ :: Lens' Args (Maybe (QCGen, Int))
replay_ = lens replay (\ a replay -> a{ replay })

data Options = Options
  { groups :: [String]
  , cases  :: [String]
  , args   :: Args
  }

groups_ :: Lens' Options [String]
groups_ = lens groups (\ o groups -> o{ groups })

args_ :: Lens' Options Args
args_ = lens args (\ o args -> o{ args })

runGroup :: Args -> Int -> Group -> Layout ()
runGroup args width Group{ groupName, cases } = incr (put "  ") $ do
  withSGR [setBold] $ lineStr groupName
  lineStr (replicate (2 + fullWidth width) '━')
  (t, _) <- listen (sequence_ (intersperse (putLn "") (map (runCase args width) cases)))
  putLn ""
  sequence_ (tally t)

runCase :: Args -> Int -> Case -> Layout ()
runCase args width Case{ name, loc = Loc{ path, lineNumber }, property } = do
  title

  res <- lift (quickCheckWithResult args property)
  let status f t
        | isSuccess res = t
        | otherwise     = f

  unless (isSuccess res) $ do
    lift clearFromCursorToLineBeginning
    lift (setCursorColumn 0)
    failure title

  put "   " *> status (failure (putLn "Failure")) (success (putLn "Success"))

  let stats = resultStats res
      details = numTests stats == maxSuccess args && not (null (classes stats))

  when (details || not (isSuccess res)) . incr (status (failure (put "╭─")) (put "  ")) . line . status failure success . putLn $ replicate (fullWidth width) '─'

  incr (status (failure (put "│ ")) (put "  ")) . v_ $ concat
    [ [ line (h_ (runStats args stats ++ runClasses stats) *> putLn "") | details ]
    , case res of
      Failure{ usedSeed, usedSize, reason, theException, failingTestCase } ->
        [ do
          lineStr (path ++ ":" ++ show lineNumber)
          lineStr reason
          for_ theException (lineStr . displayException)
          for_ failingTestCase lineStr
        , lineStr ("--replay (" ++ show usedSeed ++ "," ++ show usedSize ++ ")")
        ]
      _ -> []
    , runLabels stats
    , runTables stats
    ]
  tell (fromBool (isSuccess res))
  where
  title = incr (put "❧ ") . line $ do
    _ <- withSGR [setBold] (put (name ++ replicate (width - length name) ' '))
    lift (hFlush stdout)

data Stats = Stats
  { numTests     :: Int
  , numDiscarded :: Int
  , numShrinks   :: Int
  , labels       :: Map.Map [String] Int
  , classes      :: Map.Map String Int
  , tables       :: Map.Map String (Map.Map String Int)
  }

defaultStats :: Stats
defaultStats = Stats
  { numTests     = 0
  , numDiscarded = 0
  , numShrinks   = 0
  , labels       = Map.empty
  , classes      = Map.empty
  , tables       = Map.empty
  }

resultStats :: Result -> Stats
resultStats = \case
  Success{ numTests, numDiscarded, labels, classes, tables }                   -> defaultStats{ numTests, numDiscarded, labels, classes, tables }
  GaveUp{ numTests, numDiscarded, labels, classes, tables }                    -> defaultStats{ numTests, numDiscarded, labels, classes, tables }
  Failure{ numTests, numDiscarded, numShrinks, failingLabels, failingClasses } -> defaultStats{ numTests, numDiscarded, numShrinks, labels = Map.fromList (map ((, numTests) . pure) failingLabels), classes = Map.fromList (map (,numTests) (toList failingClasses)) }
  NoExpectedFailure{ numTests, numDiscarded, labels, classes, tables }         -> defaultStats{ numTests, numDiscarded, labels, classes, tables }

runStats :: Args -> Stats -> [Layout ()]
runStats Args{ maxSuccess } Stats{ numTests, numDiscarded, numShrinks } = [ sepBy_ (put ", ") entries *> put "." | not (null entries) ]
  where
  entries = concat
    [ [ put (show numTests ++ " test" ++ singular numTests) | numTests > 0 && numTests /= maxSuccess ]
    , [ put (show numDiscarded ++ " discarded") | numDiscarded > 0 ]
    , [ put (show numShrinks ++ " shrink" ++ singular numShrinks) | numShrinks > 0 ]
    ]


runLabels :: Stats -> [Layout ()]
runLabels Stats{ numTests, labels }
  | null labels = []
  | otherwise   = IntMap.elems numberedLabels >>= param
  where
  numberedLabels = IntMap.fromListWith (Map.unionWith (+)) $
    [ (i, Map.singleton l n)
    | (labels, n) <- Map.toList labels
    , (i, l) <- zip [(0 :: Int)..] labels
    ]
  param m =
    [ do
      for_ (zip [1..] scaled) $ \ (i, (key, v)) -> do
        lineStr $ show (i :: Int) ++ ". " ++  (' ' <$ guard (v < 10)) ++ showFFloatAlt (Just 1) v "" ++ "% " ++ key
    , do
      lineStr [ c | e <- sparked, c <- [e, e, e] ]
      lineStr [ c | k <- Map.keys m, i <- maybe [] (pure . succ) (elemIndex k (map fst sorted)), c <- ' ':show i ++ " " ]
    ]
    where
    n = realToFrac numTests :: Double
    sorted = sortBy (flip (comparing snd) <> flip (comparing fst)) (Map.toList m)
    scaled = map (fmap (\ v -> realToFrac v / n * 100)) sorted
    sparked = sparkify (map snd (Map.toList m))

runClasses :: Stats -> [Layout ()]
runClasses Stats{ numTests = n, classes } = [ put (intercalate ", " (map (uncurry (class_ n)) (Map.toList classes)) ++ ".") | not (null classes) ] where
  class_ n label n' = if n == n' then label else showFFloatAlt (Just 1) (fromIntegral n' / fromIntegral n * 100 :: Double) ('%':' ':label)

runTables :: Stats -> [Layout ()]
runTables _ = []


fullWidth :: Int -> Int
fullWidth width = width + 3 + length "Success"

plural :: Int -> a -> a -> a
plural 1 s _ = s
plural _ _ p = p

singular :: Int -> String
singular 1 = "s"
singular _ = ""

tally :: Tally -> [Layout ()]
tally t =
  [ line $ do
    sepBy_ (put ", ")
      (  [ success (put (show (successes t) ++ ' ' : plural (successes t) "success" "successes")) | hasSuccesses ]
      ++ [ failure (put (show (failures t)  ++ ' ' : plural (failures t)  "failure" "failures"))  | hasFailures  ])

    putLn "."
    putLn ""
  | hasSuccesses || hasFailures
  ]
  where
  hasSuccesses = successes t /= 0
  hasFailures = failures t /= 0


sepBy_ :: Layout () -> [Layout ()] -> Layout ()
sepBy_ sep = sequence_ . intersperse sep

h_ :: [Layout ()] -> Layout ()
h_ = sepBy_ (put " ")

v_ :: [Layout ()] -> Layout ()
v_ = sepBy_ (lineStr "")


fromBool :: Bool -> Tally
fromBool = \case
  False -> Tally 0 1
  True  -> Tally 1 0

isFailure :: Tally -> Bool
isFailure = (/= 0) . failures

data Tally = Tally { successes :: Int, failures :: Int }

instance Semigroup Tally where
  Tally s1 f1 <> Tally s2 f2 = Tally (s1 + s2) (f1 + f2)

instance Monoid Tally where
  mempty = Tally 0 0


setColour :: Color -> SGR
setColour = SetColor Foreground Vivid

setBold :: SGR
setBold = SetConsoleIntensity BoldIntensity

withSGR :: MonadIO m => [SGR] -> m a -> m a
withSGR sgr io = liftIO (setSGR sgr) *> io <* liftIO (setSGR [])

colour :: MonadIO m => Color -> m a -> m a
colour c = withSGR [setColour c]

success, failure :: MonadIO m => m a -> m a

success = colour Green
failure = colour Red

tropical :: Group
tropical = Group
  { groupName = "Test.Group.Tropical"
  , cases =
    [ semigroupAssoc
    , monoidIdentity
    ]
  }
  where
  semigroupAssoc = Case{ name = "semigroup assoc", loc = here, property = QC.property (\ (ArbTropical a) (ArbTropical b) (ArbTropical c) -> a <> (b <> c) === (a <> b) <> c) }
  monoidIdentity = Case{ name = "monoid identity", loc = here, property = QC.property (\ (ArbTropical a) -> (mempty <> a) === a .&&. (a <> mempty) === a)}

newtype ArbTropical = ArbTropical (Tropical Int)
  deriving (Eq, Ord, Show)

instance QC.Arbitrary ArbTropical where
  arbitrary = QC.oneof
    [ pure (ArbTropical (Tropical Nothing))
    , ArbTropical . Tropical . Just <$> QC.arbitrary
    ]


sparks :: String
sparks = " ▁▂▃▄▅▆▇█"

sparkify :: Real a => [a] -> String
sparkify bins = sparkifyRelativeTo sparks (maximum bins) bins

sparkifyRelativeTo :: Real a => String -> a -> [a] -> String
sparkifyRelativeTo sparks max = fmap spark
  where
  spark n = sparks !! round (realToFrac n / realToFrac max * realToFrac (length sparks - 1) :: Double)


newtype Layout a = Layout { runLayout :: IO () -> IO (Tally, a) }

instance Functor Layout where
  fmap f = Layout . (fmap (fmap f) .) . runLayout

instance Applicative Layout where
  pure = lift . pure
  Layout f <*> Layout a = Layout (liftA2 (<*>) <$> f <*> a)

instance Monad Layout where
  Layout m >>= f = Layout (\ i -> do
    (t1, a) <- m i
    (t2, a') <- runLayout (f a) i
    let t = t1 <> t2
    pure $ t `seq` (t, a'))

instance MonadIO Layout where
  liftIO = lift

lift :: IO a -> Layout a
lift = Layout . const . fmap (mempty,)

tell :: Tally -> Layout ()
tell = Layout . const . pure . (,())

listen :: Layout a -> Layout (Tally, a)
listen m = Layout $ \ i -> do
  (t, a) <- runLayout m i
  pure (t, (t, a))

incr :: IO () -> Layout a -> Layout a
incr j m = Layout (\ i -> runLayout m (i *> j))

line :: Layout a -> Layout a
line m = Layout (\ i -> i *> runLayout m i)

lineStr :: String -> Layout ()
lineStr s = line $ putLn s

put :: MonadIO m => String -> m ()
put = liftIO . putStr

putLn :: MonadIO m => String -> m ()
putLn = liftIO . putStrLn
