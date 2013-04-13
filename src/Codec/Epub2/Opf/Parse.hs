-- Copyright: 2010-2013 Dino Morelli
-- License: BSD3 (see LICENSE)
-- Author: Dino Morelli <dino@ui3.info>

{-# LANGUAGE Arrows #-}
{-# LANGUAGE FlexibleContexts #-}

-- | Module for extracting the metadata from an ePub file
module Codec.Epub2.Opf.Parse
   ( parseXmlToOpf
   , parseEpub2Opf
   )
   where

import Control.Applicative
import Control.Arrow.ListArrows
import Control.Monad.Error
import Data.Tree.NTree.TypeDefs ( NTree )
import Text.XML.HXT.Arrow.Namespace ( propagateNamespaces )
import Text.XML.HXT.Arrow.XmlArrow
import Text.XML.HXT.Arrow.XmlState ( no, runX, withValidate )
import Text.XML.HXT.Arrow.ReadDocument ( readString )
import Text.XML.HXT.DOM.TypeDefs

import Codec.Epub2.IO
import Codec.Epub2.Opf.Package


-- HXT helpers

{- Not used at this time. But may be used someday

atTag :: (ArrowXml a) => String -> a (NTree XNode) XmlTree
atTag tag = deep (isElem >>> hasName tag)
-}

atQTag :: (ArrowXml a) => QName -> a (NTree XNode) XmlTree
atQTag tag = deep (isElem >>> hasQName tag)

text :: (ArrowXml a) => a (NTree XNode) String
text = getChildren >>> getText

notNullA :: (ArrowList a) => a [b] [b]
notNullA = isA $ not . null


{- Not used at this time, we don't have any single but optional
   tags any longer

mbQTagText :: (ArrowXml a) => QName -> a (NTree XNode) (Maybe String)
mbQTagText tag =
   ( atQTag tag >>>
     text >>> notNullA >>> arr Just )
   `orElse`
   (constA Nothing)
-}


mbGetAttrValue :: (ArrowXml a) =>
   String -> a XmlTree (Maybe String)
mbGetAttrValue n =
   (getAttrValue n >>> notNullA >>> arr Just)
   `orElse` (constA Nothing)

mbGetQAttrValue :: (ArrowXml a) =>
   QName -> a XmlTree (Maybe String)
mbGetQAttrValue qn =
   (getQAttrValue qn >>> notNullA >>> arr Just)
   `orElse` (constA Nothing)


{- ePub parsing helpers

   Note that these URIs could conceivably change in the future
   Is it ok that they're hardcoded like this?

   Well, ok, the xml namespace URI will probably never change.
-}

dcName, opfName, xmlName :: String -> QName
dcName local = mkQName "dc" local "http://purl.org/dc/elements/1.1/"
opfName local = mkQName "opf" local "http://www.idpf.org/2007/opf"
xmlName local = mkQName "xml" local "http://www.w3.org/XML/1998/namespace"


getPackage :: (ArrowXml a) => a (NTree XNode) (String, String)
getPackage = atQTag (opfName "package") >>>
   proc x -> do
      v <- getAttrValue "version" -< x
      u <- getAttrValue "unique-identifier" -< x
      returnA -< (v, u)


getTitle :: (ArrowXml a) => a (NTree XNode) Title
getTitle = atQTag (dcName "title") >>>
   proc x -> do
      l <- mbGetQAttrValue (xmlName "lang") -< x
      c <- text -< x
      returnA -< Title l c


{- Since creators and contributors have the same exact XML structure,
   this arrow is used to get either of them
-}
getCreator :: (ArrowXml a) => String -> a (NTree XNode) Creator
getCreator tag = atQTag (dcName tag) >>> ( unwrapArrow $ Creator
   <$> (WrapArrow $ mbGetQAttrValue (opfName "role"))
   <*> (WrapArrow $ mbGetQAttrValue (opfName "file-as"))
   <*> (WrapArrow $ text)
   )


getSubject :: (ArrowXml a) => a (NTree XNode) String
getSubject = atQTag (dcName "subject") >>> text


getDescription :: (ArrowXml a) => a (NTree XNode) Description
getDescription = atQTag (dcName "description") >>>
   proc x -> do
      l <- mbGetQAttrValue (xmlName "lang") -< x
      c <- text -< x
      returnA -< Description l c


getPublisher :: (ArrowXml a) => a (NTree XNode) String
getPublisher = atQTag (dcName "publisher") >>> text


getDate :: (ArrowXml a) => a (NTree XNode) Date
getDate = atQTag (dcName "date") >>>
   proc x -> do
      e <- mbGetQAttrValue (opfName "event") -< x
      c <- text -< x
      returnA -< Date e c


getType :: (ArrowXml a) => a (NTree XNode) String
getType = atQTag (dcName "type") >>> text


getFormat :: (ArrowXml a) => a (NTree XNode) String
getFormat = atQTag (dcName "format") >>> text


getId :: (ArrowXml a) => a (NTree XNode) Identifier
getId = atQTag (dcName "identifier") >>>
   proc x -> do
      mbi <- mbGetAttrValue "id" -< x
      s <- mbGetQAttrValue (opfName "scheme") -< x
      c <- text -< x
      let i = maybe "[WARNING: missing required id attribute]" id mbi
      returnA -< Identifier i s c


getSource :: (ArrowXml a) => a (NTree XNode) String
getSource = atQTag (dcName "source") >>> text


getLang :: (ArrowXml a) => a (NTree XNode) String
getLang = atQTag (dcName "language") >>> text


getRelation :: (ArrowXml a) => a (NTree XNode) String
getRelation = atQTag (dcName "relation") >>> text


getCoverage :: (ArrowXml a) => a (NTree XNode) String
getCoverage = atQTag (dcName "coverage") >>> text


getRights :: (ArrowXml a) => a (NTree XNode) String
getRights = atQTag (dcName "rights") >>> text


getMeta :: (ArrowXml a) => a (NTree XNode) Metadata
getMeta = atQTag (opfName "metadata") >>> ( unwrapArrow $ Metadata
   <$> (WrapArrow $ listA getTitle)
   <*> (WrapArrow $ listA $ getCreator "creator")
   <*> (WrapArrow $ listA $ getCreator "contributor")
   <*> (WrapArrow $ listA getSubject)
   <*> (WrapArrow $ listA getDescription)
   <*> (WrapArrow $ listA getPublisher)
   <*> (WrapArrow $ listA getDate)
   <*> (WrapArrow $ listA getType)
   <*> (WrapArrow $ listA getFormat)
   <*> (WrapArrow $ listA getId)
   <*> (WrapArrow $ listA getSource)
   <*> (WrapArrow $ listA getLang)
   <*> (WrapArrow $ listA getRelation)
   <*> (WrapArrow $ listA getCoverage)
   <*> (WrapArrow $ listA getRights)
   )


getManifestItem :: (ArrowXml a) => a (NTree XNode) ManifestItem
getManifestItem = atQTag (opfName "item") >>>
   proc x -> do
      i <- getAttrValue "id" -< x
      h <- getAttrValue "href" -< x
      m <- getAttrValue "media-type" -< x
      returnA -< ManifestItem i h m


getManifest :: (ArrowXml a) => a (NTree XNode) [ManifestItem]
getManifest = atQTag (opfName "manifest") >>>
   proc x -> do
      l <- listA getManifestItem -< x
      returnA -< l


getSpineItemref :: (ArrowXml a) => a (NTree XNode) SpineItemref
getSpineItemref = atQTag (opfName "itemref") >>>
   proc x -> do
      i <- getAttrValue "idref" -< x
      ml <- mbGetAttrValue "linear" -< x
      let l = maybe Nothing (\v -> if v == "no" then Just False else Just True) ml
      returnA -< SpineItemref i l


getSpine :: (ArrowXml a) => a (NTree XNode) Spine
getSpine = atQTag (opfName "spine") >>>
   proc x -> do
      i <- getAttrValue "toc" -< x
      l <- listA getSpineItemref -< x
      returnA -< (Spine i l)


getGuideRef :: (ArrowXml a) => a (NTree XNode) GuideRef
getGuideRef = atQTag (opfName "reference") >>>
   proc x -> do
      t <- getAttrValue "type" -< x
      mt <- mbGetAttrValue "title" -< x
      h <- getAttrValue "href" -< x
      returnA -< GuideRef t mt h


getGuide :: (ArrowXml a) => a (NTree XNode) [GuideRef]
getGuide = atQTag (opfName "guide") >>>
   proc x -> do
      l <- listA getGuideRef -< x
      returnA -< l


getBookData :: (ArrowXml a) => a (NTree XNode) Package
getBookData = 
   proc x -> do
      (v, u) <- getPackage -< x
      m <- getMeta -< x
      mf <- getManifest -< x
      sp <- getSpine -< x
      gl <- listA getGuide -< x
      let g = case gl of
                []  -> []
                [e] -> e
                _   -> error "ERROR: more than one guide entries"        
      returnA -< (Package v u m mf sp g)


{- | Extract the ePub OPF Package data contained in the supplied 
   XML string
-}
parseXmlToOpf :: (MonadIO m, MonadError String m) =>
   String -> m Package
parseXmlToOpf contents = do
   {- Improper encoding and schema declarations have been causing
      havok with this parse, cruelly strip them out. -}
   let cleanedContents = removeIllegalStartChars . removeEncoding
         . removeDoctype $ contents
   
   result <- liftIO $ runX (
      readString [withValidate no] cleanedContents
      >>> propagateNamespaces
      >>> getBookData
      )

   case result of
      (p : []) -> return p
      _        -> throwError
         "ERROR: Parse didn't result in a single document metadata"


-- | Given the path to an ePub file, extract the OPF Package data
parseEpub2Opf :: (MonadIO m, MonadError String m) =>
   FilePath -> m Package
parseEpub2Opf zipPath = do
   (_, contents) <- opfContentsFromZip zipPath
   parseXmlToOpf contents