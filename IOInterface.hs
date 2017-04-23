module IOInterface (
  writeObjectToFile,
  readObjectFromFile
) where

import qualified Objects as O
import qualified Codec.Compression.Zlib as Zlib
import qualified Data.ByteString.Lazy as B
import qualified ObjectStore as OS
import qualified Data.ByteString.Char8 as C
import Control.Monad 
import Control.Monad.Except
import System.Directory (createDirectoryIfMissing, listDirectory,
                         doesDirectoryExist,doesFileExist)
import System.FilePath (splitFileName)
import RepoMonad
type Author = C.ByteString
type Message = C.ByteString

commit ::  (RepoMonad m, Monad m, MonadIO m ) => 
           OS.Repo -> [OS.Ref] -> Author -> Message -> m O.ObjectId
commit r refs a m = do
  objectIds <- commitDirectories r r
  let tree = O.makeTree objectIds
  filename <- writeObjectToFile r tree
  let c = O.makeCommit refs filename a m
  writeObjectToFile r c

commitDirectories :: (RepoMonad m, Monad m, MonadIO m ) => FilePath -> OS.Repo -> 
                     m [(O.EntryType, O.ObjectId, O.ObjectName)]
commitDirectories fp r = do 
    filePaths <- liftIO $ listDirectory fp
    foldr commit' (return []) filePaths where
    commit' dir acc = commitEachDirectory dir r `mappend` acc
    commitEachDirectory filepath r = do
        entry <- commitDirectory filepath r
        case entry of
          Just x  -> return [entry]
          Nothing -> return []

commitDirectory :: (RepoMonad m, Monad m, MonadIO m ) => FilePath -> OS.Repo -> 
                   m (Maybe (O.EntryType, O.ObjectId, O.ObjectName))
commitDirectory filePath r = 
  if (head . snd . splitFileName) filePath == '.' then return Nothing else do
  isDirectory <- liftIO $ doesDirectoryExist filePath
  isFile <- liftIO $ doesFileExist filePath 
  case (isDirectory, isFile) of  
    (True, _) -> do 
        objectIds <- commitDirectories filePath r
        let tree = O.makeTree objectIds
        filename <- writeObjectToFile r tree
        return $ Just (O.makeTreeEntryType, filename, C.pack filePath)
    (_, True) -> do
         contents <- liftIO $ C.readFile filePath
         let blob = O.makeBlob contents
         fileName <- writeObjectToFile r blob
         return $ Just (O.makeBlobEntryType, fileName, C.pack filePath)
    (_,_)  ->  return Nothing 


--ASSUMPTION NO REMOTES
--readRefs OS.Repo    

createEmptyRepo :: OS.Repo -> IO ()
createEmptyRepo repo = Prelude.mapM_ (createDirectoryIfMissing True) folders
    where folders = [repo ++ "/.hit/objects", repo ++ "/.hit/refs/heads"]

initialize ::(RepoMonad m, Monad m, MonadIO m) => OS.Repo -> OS.RefStore -> m OS.RefStore
initialize r ref = do
  dexists <- liftIO $ doesDirectoryExist (r ++ "/.hit") 
  if dexists then do
    liftIO $ Prelude.putStrLn "Reinitializing git directory"
    readRefs r ref
  else do
    liftIO $ createEmptyRepo r >>
             Prelude.putStrLn "Initializing git directory" >>
             Prelude.writeFile (r ++ "/.git/refs/HEAD") "refs: refs/heads/master"
    return ref

userInterface :: (RepoMonad m, Monad m, MonadIO m) => m()
userInterface = go (OS.createRef) where
  go :: (RepoMonad m, Monad m, MonadIO m) => OS.RefStore -> m()
  go refMap = do
    liftIO $ Prelude.putStr "hit> "
    str <- liftIO $ Prelude.getLine
    case str of
      "init" -> initialize "./" refMap >>= go
      "commit" -> do
                  refMap' <- readRefs "./" refMap
                  head <- getHeadRef "./"
                  commitId <- commit "./" [head] (C.pack "Brendon") 
                              (C.pack "default msg")
                  setHead "./" "master" commitId
                  liftIO $ putStrLn ("Commit ID: " ++ C.unpack commitId) >> go refMap'
      "exit" -> do 
                 --print refMap
                 return ()
      _      -> liftIO $ Prelude.putStrLn "Unrecognized command" >> go refMap

