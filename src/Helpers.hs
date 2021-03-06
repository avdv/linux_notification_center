{-# LANGUAGE OverloadedStrings #-}

module Helpers where

import qualified Data.ConfigFile as CF
import qualified Control.Monad.Except as Error
import Control.Applicative ((<|>))
import Data.Maybe (fromMaybe)
import Data.Functor (fmap)
--import Data.Sequence (drop)
import Text.HTML.TagSoup

import qualified Data.Text as Text
import Data.Char ( chr )
import Text.I18N.GetText (textDomain, bindTextDomain, getText)
import System.Locale.SetLocale (setLocale, Category(LC_ALL))
import System.IO.Unsafe (unsafePerformIO)
import System.Environment (getExecutablePath)

initI18n = do
  setLocale LC_ALL (Just "")
  mypath <- getExecutablePath
  bindTextDomain "deadd-notification-center"
    (Just ((reverse $ removeFromLastSlash (reverse mypath))
            ++ "/../share/locale/"))
  textDomain (Just "deadd-notification-center")

removeFromLastSlash :: String -> String
removeFromLastSlash ('/':as) = as
removeFromLastSlash (a:as) = removeFromLastSlash as

translate :: String -> String
translate = unsafePerformIO . getText

readConfig :: CF.Get_C a => a -> CF.ConfigParser -> String -> String -> a
readConfig defaultVal conf sec opt = fromEither defaultVal
  $ fromEither (Right defaultVal) $ Error.runExceptT $ CF.get conf sec opt

readConfigFile :: String -> IO CF.ConfigParser
readConfigFile path = do
  c <- Error.catchError (CF.readfile CF.emptyCP{CF.optionxform = id} path)
    (\e ->  do
        putStrLn $ show e
        return $ return CF.emptyCP)
  let c1 = fromEither CF.emptyCP c
  return c1

fromEither :: a -> Either b a -> a
fromEither a e = case e of
  Left _ -> a
  Right x -> x

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right b) = Just b
eitherToMaybe _ = Nothing

replace a b c = replace' c a b
replace' :: Eq a => [a] -> [a] -> [a] -> [a]
replace' [] _ _ = []
replace' s find repl =
    if take (length find) s == find
        then repl ++ (replace' (drop (length find) s) find repl)
        else [head s] ++ (replace' (tail s) find repl)

-- split a string at ":"
split :: String -> [String]
split ('"':':':'"':ds) = "" : split ds
split (a:[]) = [[a]]
split (a:bs) = (a:(split bs !! 0)): (tail $ split bs)
split [] = []

splitOn :: Char -> String -> [String]
splitOn c s = case rest of
                []     -> [chunk]
                _:rest -> chunk : splitOn c rest
  where (chunk, rest) = break (==c) s


trimFront :: String -> String
trimFront (' ':ss) = trimFront ss
trimFront ss = ss

trimBack :: String -> String
trimBack = reverse . trimFront . reverse

trim :: String -> String
trim = trimBack . trimFront

isPrefix :: String -> String -> Bool
isPrefix (a:pf) (b:s) = a == b && isPrefix pf s
isPrefix [] _ = True
isPrefix _ _ = False

removeOuterLetters (a:as) = reverse $ tail $ reverse as
removeOuterLetters [] = []


splitEvery :: Int -> [a] -> [[a]]
splitEvery _ [] = []
splitEvery n as = (take n as) : (splitEvery n $ tailAt n as)
  where
    tailAt 0 as = as
    tailAt n (a:as) = tailAt (n - 1) as
    tailAt _ [] = []

markupify :: Text.Text -> Text.Text
markupify = renderTags . filterTags . canonicalizeTags . parseTags

atMay :: [a] -> Int -> Maybe a
atMay ls i = if length ls > i then
  Just $ ls !! i else Nothing

-- The following tags should be supported:
-- <b> ... </b> 	Bold
-- <i> ... </i> 	Italic
-- <u> ... </u> 	Underline
-- <a href="..."> ... </a> 	Hyperlink
supportedTags = ["b", "i", "u", "a"]

filterTags :: [Tag Text.Text] -> [Tag Text.Text]
filterTags [] = []
filterTags (tag : rest) = case tag of
  TagText _        -> keep
  TagOpen "img" _  -> process "img" skip
  TagOpen name _   ->
    let conversion = if isSupported name then enclose name else strip
    in process name conversion
  otherwise        -> next
  where
    isSupported name = elem name supportedTags

    keep = tag : next
    next = filterTags rest

    skip _ = []
    strip  = filterTags
    enclose name i = tag : (filterTags i) ++ [TagClose name]

    process name conversion =
      let
        (inner, endTagRest) = break (isTagCloseName name) rest
      in (conversion inner) ++ (filterTags endTagRest)
