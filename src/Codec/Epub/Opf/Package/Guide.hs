-- Copyright: 2010 Dino Morelli
-- License: BSD3 (see LICENSE)
-- Author: Dino Morelli <dino@ui3.info>

{- | Data types for working with the metadata of ePub documents

   These data types were constructed by studying the IDPF OPF 
   specification for ePub documents found here:

   <http://www.idpf.org/2007/opf/OPF_2.0_final_spec.html>
-}
module Codec.Epub.Opf.Package.Guide
   ( EpubGuideRef (..)
   )
   where


-- | opf:guide
data EpubGuideRef = EpubGuideRef
   { egType :: String -- Must follow 13th edition of the Chicago Manual of Style
   , egTitle :: Maybe String
   , egHref :: String -- Must reference item in manifest
   }
   deriving (Eq, Show)