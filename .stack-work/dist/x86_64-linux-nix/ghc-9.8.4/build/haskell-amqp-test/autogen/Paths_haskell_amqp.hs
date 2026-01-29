{-# LANGUAGE CPP #-}
{-# LANGUAGE NoRebindableSyntax #-}
#if __GLASGOW_HASKELL__ >= 810
{-# OPTIONS_GHC -Wno-prepositive-qualified-module #-}
#endif
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -w #-}
module Paths_haskell_amqp (
    version,
    getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir,
    getDataFileName, getSysconfDir
  ) where


import qualified Control.Exception as Exception
import qualified Data.List as List
import Data.Version (Version(..))
import System.Environment (getEnv)
import Prelude


#if defined(VERSION_base)

#if MIN_VERSION_base(4,0,0)
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#else
catchIO :: IO a -> (Exception.Exception -> IO a) -> IO a
#endif

#else
catchIO :: IO a -> (Exception.IOException -> IO a) -> IO a
#endif
catchIO = Exception.catch

version :: Version
version = Version [0,1,0,0] []

getDataFileName :: FilePath -> IO FilePath
getDataFileName name = do
  dir <- getDataDir
  return (dir `joinFileName` name)

getBinDir, getLibDir, getDynLibDir, getDataDir, getLibexecDir, getSysconfDir :: IO FilePath




bindir, libdir, dynlibdir, datadir, libexecdir, sysconfdir :: FilePath
bindir     = "/home/pirackr/Working/github.com/pirackr/haskell-amqp/.stack-work/install/x86_64-linux-nix/a8a1ff2e32894ea69832b61b81a6d368a4138fca16db531d6613adf27b46040f/9.8.4/bin"
libdir     = "/home/pirackr/Working/github.com/pirackr/haskell-amqp/.stack-work/install/x86_64-linux-nix/a8a1ff2e32894ea69832b61b81a6d368a4138fca16db531d6613adf27b46040f/9.8.4/lib/x86_64-linux-ghc-9.8.4/haskell-amqp-0.1.0.0-CyxWoJ6AbS5Fc8KaH3ETDc-haskell-amqp-test"
dynlibdir  = "/home/pirackr/Working/github.com/pirackr/haskell-amqp/.stack-work/install/x86_64-linux-nix/a8a1ff2e32894ea69832b61b81a6d368a4138fca16db531d6613adf27b46040f/9.8.4/lib/x86_64-linux-ghc-9.8.4"
datadir    = "/home/pirackr/Working/github.com/pirackr/haskell-amqp/.stack-work/install/x86_64-linux-nix/a8a1ff2e32894ea69832b61b81a6d368a4138fca16db531d6613adf27b46040f/9.8.4/share/x86_64-linux-ghc-9.8.4/haskell-amqp-0.1.0.0"
libexecdir = "/home/pirackr/Working/github.com/pirackr/haskell-amqp/.stack-work/install/x86_64-linux-nix/a8a1ff2e32894ea69832b61b81a6d368a4138fca16db531d6613adf27b46040f/9.8.4/libexec/x86_64-linux-ghc-9.8.4/haskell-amqp-0.1.0.0"
sysconfdir = "/home/pirackr/Working/github.com/pirackr/haskell-amqp/.stack-work/install/x86_64-linux-nix/a8a1ff2e32894ea69832b61b81a6d368a4138fca16db531d6613adf27b46040f/9.8.4/etc"

getBinDir     = catchIO (getEnv "haskell_amqp_bindir")     (\_ -> return bindir)
getLibDir     = catchIO (getEnv "haskell_amqp_libdir")     (\_ -> return libdir)
getDynLibDir  = catchIO (getEnv "haskell_amqp_dynlibdir")  (\_ -> return dynlibdir)
getDataDir    = catchIO (getEnv "haskell_amqp_datadir")    (\_ -> return datadir)
getLibexecDir = catchIO (getEnv "haskell_amqp_libexecdir") (\_ -> return libexecdir)
getSysconfDir = catchIO (getEnv "haskell_amqp_sysconfdir") (\_ -> return sysconfdir)



joinFileName :: String -> String -> FilePath
joinFileName ""  fname = fname
joinFileName "." fname = fname
joinFileName dir ""    = dir
joinFileName dir fname
  | isPathSeparator (List.last dir) = dir ++ fname
  | otherwise                       = dir ++ pathSeparator : fname

pathSeparator :: Char
pathSeparator = '/'

isPathSeparator :: Char -> Bool
isPathSeparator c = c == '/'
