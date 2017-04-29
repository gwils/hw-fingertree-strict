{-# LANGUAGE CPP                   #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
#if __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Safe                  #-}
#endif
#if __GLASGOW_HASKELL__ >= 710
{-# LANGUAGE AutoDeriveTypeable    #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.PriorityQueue.FingerTree
-- Copyright   :  (c) Ross Paterson 2008
-- License     :  BSD-style
-- Maintainer  :  R.Paterson@city.ac.uk
-- Stability   :  experimental
-- Portability :  non-portable (MPTCs and functional dependencies)
--
-- Interval maps implemented using the 'FingerTree' type, following
-- section 4.8 of
--
--  * Ralf Hinze and Ross Paterson,
--    \"Finger trees: a simple general-purpose data structure\",
--    /Journal of Functional Programmaxg/ 16:2 (2006) pp 197-217.
--    <http://staff.city.ac.uk/~ross/papers/FingerTree.html>
--
-- An amortized running time is given for each operation, with /n/
-- referring to the size of the priority queue.  These bounds hold even
-- in a persistent (shared) setting.
--
-- /Note/: Many of these operations have the same names as similar
-- operations on lists in the "Prelude".  The ambiguity may be resolved
-- using either qualification or the @hiding@ clause.
--
-----------------------------------------------------------------------------

module HaskellWorks.Data.SegmentMap.FingerTree.Strict
  ( -- * Segments
    Segment(..), point,
    -- * Segment maps
    SegmentMap(..),
    OrderedMap(..),
    delete,
    empty,
    fromList,
    insert,
    singleton,
    update,
    segmentMapToList,

    Item(..),
    cappedL,
    cappedR,
    capR,
    capL
    ) where

import           HaskellWorks.Data.FingerTree.Strict (FingerTree, Measured (..), ViewL (..), ViewR (..), viewl, viewr, (<|), (><), (|>))
import qualified HaskellWorks.Data.FingerTree.Strict as FT

import Control.Applicative ((<$>))
import Data.Foldable       (Foldable (foldMap), toList)
import Data.Semigroup
import Data.Traversable    (Traversable (traverse))

----------------------------------
-- 4.8 Application: segment trees
----------------------------------

-- | A closed segment.  The lower bound should be less than or equal
-- to the higher bound.
data Segment k = Segment { low :: !k, high :: !k }
    deriving (Eq, Ord, Show)

-- | An segment in which the lower and upper bounds are equal.
point :: k -> Segment k
point k = Segment k k

data Item k a = Item !k !a deriving (Eq, Show)

instance Functor (Item k) where
    fmap f (Item i t) = Item i (f t)

instance Foldable (Item k) where
    foldMap f (Item _ x) = f x

instance Traversable (Item k) where
    traverse f (Item i x) = Item i <$> f x

instance (Monoid k) => Measured k (Segment k) where
  measure = low

instance (Monoid k) => Measured k (Item k a) where
  measure (Item k _) = k

-- | Map of closed segments, possibly with duplicates.
-- The 'Foldable' and 'Traversable' instances process the segments in
-- lexicographical order.

newtype OrderedMap k a = OrderedMap (FingerTree k (Item k a)) deriving Show

newtype SegmentMap k a = SegmentMap (OrderedMap (Max k) (Segment k, a)) deriving Show

-- ordered lexicographically by segment start

instance Functor (OrderedMap k) where
    fmap f (OrderedMap t) = OrderedMap (FT.unsafeFmap (fmap f) t)

instance Foldable (OrderedMap k) where
    foldMap f (OrderedMap t) = foldMap (foldMap f) t

instance Traversable (OrderedMap k) where
    traverse f (OrderedMap t) = OrderedMap <$> FT.unsafeTraverse (traverse f) t

instance Functor (SegmentMap k) where
    fmap f (SegmentMap t) = SegmentMap (fmap (fmap f) t)

-- instance Foldable (SegmentMap k) where
--     foldMap f (SegmentMap t) = foldMap (foldMap f) t

segmentMapToList :: SegmentMap k a -> [(Segment k, a)]
segmentMapToList (SegmentMap m) = toList m

-- instance Traversable (SegmentMap k) where
--     traverse f (SegmentMap t) =
--         SegmentMap <$> FT.unsafeTraverse (traverse f) t

-- | /O(1)/.  The empty segment map.
empty :: (Ord k, Bounded k) => SegmentMap k a
empty = SegmentMap (OrderedMap FT.empty)

-- | /O(1)/.  Segment map with a single entry.
singleton :: (Bounded k, Ord k) => Segment k -> a -> SegmentMap k a
singleton s@(Segment lo hi) a = SegmentMap $ OrderedMap $ FT.singleton $ Item (Max lo) (s, a)

delete :: forall k a. (Bounded k, Ord k, Enum k, Eq a)
       => Segment k
       -> SegmentMap k a
       -> SegmentMap k a
delete = flip update Nothing

insert :: forall k a. (Bounded k, Ord k, Enum k, Eq a)
       => Segment k
       -> a
       -> SegmentMap k a
       -> SegmentMap k a
insert s a = update s (Just a)

update :: forall k a. (Ord k, Enum k, Bounded k, Eq a)
       => Segment k
       -> Maybe a
       -> SegmentMap k a
       -> SegmentMap k a
update (Segment lo hi)   _        m | lo > hi    = m
update _                 Nothing  m              = m
update s@(Segment lo hi) (Just x) (SegmentMap (OrderedMap t)) =
  SegmentMap $ OrderedMap (cappedL lo lt >< Item (Max lo) (s, x) <| cappedR hi rt)
  where
    (lt, ys) = FT.split (>= Max lo) t
    (zs, remainder) = FT.split (> Max hi) ys
    e = maybe FT.Empty FT.singleton (FT.maybeLast zs >>= capR hi)
    rt = e >< remainder

cappedL :: (Enum k, Ord k, Bounded k)
  => k
  -> FingerTree (Max k) (Item (Max k) (Segment k, a))
  -> FingerTree (Max k) (Item (Max k) (Segment k, a))
cappedL lo t = case viewr t of
  EmptyR   -> t
  ltp :> n -> maybe ltp (ltp |>) (capL lo n)

cappedR :: (Enum k, Ord k, Bounded k)
  => k
  -> FingerTree (Max k) (Item (Max k) (Segment k, a))
  -> FingerTree (Max k) (Item (Max k) (Segment k, a))
cappedR hi t = case viewl t of
  EmptyL   -> t
  n :< rtp -> maybe rtp (<| rtp) (capR hi n)

capL :: (Ord k, Enum k)
  => k
  -> Item (Max k) (Segment k, a)
  -> Maybe (Item (Max k) (Segment k, a))
capL rilo n@(Item _ (Segment lilo lihi, a))
  | rilo <  lilo = Nothing
  | rilo <= lihi = Just $ Item (Max lilo) (Segment lilo (pred rilo), a)
  | otherwise    = Just n

capR :: (Ord k, Enum k)
  => k
  -> Item (Max k) (Segment k, a)
  -> Maybe (Item (Max k) (Segment k, a))
capR lihi n@(Item _ (Segment rilo rihi, a))
  | lihi <  rilo = Just n
  | lihi <= rihi = Just $ Item (Max (succ lihi)) (Segment (succ lihi) rihi, a)
  | otherwise    = Nothing

fromList :: (Ord v, Enum v, Eq a, Bounded v)
  => [(Segment v, a)]
  -> SegmentMap v a

fromList = foldr (uncurry insert) empty
