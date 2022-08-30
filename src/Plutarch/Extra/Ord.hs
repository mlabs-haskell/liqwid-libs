{-# LANGUAGE TypeApplications #-}
-- Needed to 'link' Ordering and POrdering
{-# OPTIONS_GHC -Wno-orphans #-}

{- |
 Module: Plutarch.Extra.Ord
 Copyright: (C) Liqwid Labs 2022
 License: Apache 2.0
 Maintainer: Koz Ross <koz@mlabs.city>
 Portability: GHC only
 Stability: Experimental

 Ordering-related helpers and functionality.
-}
module Plutarch.Extra.Ord (
    -- * Types
    POrdering (..),
    PComparator,

    -- * Functions

    -- ** Creating comparators
    pfromOrd,
    pfromOrdBy,

    -- ** Combining comparators
    pproductComparator,
    psumComparator,

    -- ** Transforming comparators
    pmapComparator,
    preverseComparator,

    -- ** Using comparators
    pcompareBy,
    pequateBy,
    psort,
    psortBy,
) where

import Data.Semigroup (Semigroup (stimes), stimesIdempotentMonoid)
import Plutarch.Extra.List (plist, pmatchList, psingletonUnhoisted)
import Plutarch.Internal.PlutusType (PlutusType (pcon', pmatch'))
import Plutarch.Lift (
    PConstantDecl (
        PConstantRepr,
        PConstanted,
        pconstantFromRepr,
        pconstantToRepr
    ),
    PUnsafeLiftDecl (PLifted),
 )
import qualified Plutarch.List as PList

{- | Sorts a list-like structure full of a 'POrd' instance.

 This uses [merge sort](https://en.wikipedia.org/wiki/Merge_sort), which is
 also [stable](https://en.wikipedia.org/wiki/Sorting_algorithm#Stability).
 This means that it requires a linearithmic ($n \log(n)$) number of
 comparisons, as with all comparison sorts.

 @since 3.4.0
-}
psort ::
    forall (a :: S -> Type) (ell :: (S -> Type) -> S -> Type) (s :: S).
    (POrd a, PElemConstraint ell a, PElemConstraint ell (ell a), PListLike ell) =>
    Term s (ell a :--> ell a)
psort = phoistAcyclic $ plam $ \xs -> psortBy # pfromOrd @a # xs

{- | As 'psort', but using a custom 'PComparator'.

 @since 3.4.0
-}
psortBy ::
    forall (a :: S -> Type) (ell :: (S -> Type) -> S -> Type) (s :: S).
    (PElemConstraint ell a, PElemConstraint ell (ell a), PListLike ell) =>
    Term s (PComparator a :--> ell a :--> ell a)
psortBy = phoistAcyclic $
    plam $ \cmp xs ->
        pmergeAll # cmp #$ pmergeStart_2_3 # cmp # xs

{- | A representation of a comparison at the Plutarch level. Equivalent to
 'Ordering' in Haskell.

 @since 3.4.0
-}
data POrdering (s :: S)
    = -- | Indicates a less-than relationship.
      --
      -- @since 3.4.0
      PLT
    | -- | Indicates equality.
      --
      -- @since 3.4.0
      PEQ
    | -- | Indicates a greater-than relationship.
      --
      -- @since 3.4.0
      PGT
    deriving stock
        ( -- | @since 3.4.0
          Show
        )

-- | @since 3.4.0
instance PUnsafeLiftDecl POrdering where
    type PLifted POrdering = Ordering

-- | @since 3.4.0
instance PConstantDecl Ordering where
    type PConstantRepr Ordering = Integer
    type PConstanted Ordering = POrdering
    pconstantToRepr = \case
        LT -> 0
        EQ -> 1
        GT -> 2
    pconstantFromRepr = \case
        0 -> pure LT
        1 -> pure EQ
        2 -> pure GT
        _ -> Nothing

-- | @since 3.4.0
instance PlutusType POrdering where
    type PInner POrdering = PInteger
    pcon' = \case
        PLT -> 0
        PEQ -> 1
        PGT -> 2
    pmatch' x f =
        pif
            (x #== 0)
            (f PLT)
            ( pif
                (x #== 1)
                (f PEQ)
                (f PGT)
            )

-- | @since 3.4.0
instance PEq POrdering where
    x #== y = pmatch x $ \case
        PLT -> pmatch y $ \case
            PLT -> pcon PTrue
            _ -> pcon PFalse
        PEQ -> pmatch y $ \case
            PEQ -> pcon PTrue
            _ -> pcon PFalse
        PGT -> pmatch y $ \case
            PGT -> pcon PTrue
            _ -> pcon PFalse

-- | @since 3.4.0
instance Semigroup (Term s POrdering) where
    x <> y = pmatch x $ \case
        PLT -> pcon PLT
        PEQ -> y
        PGT -> pcon PGT
    stimes = stimesIdempotentMonoid

-- | @since 3.4.0
instance Monoid (Term s POrdering) where
    mempty = pcon PEQ

-- TODO: PShow, PPartialOrd, POrd

-- | @since 3.4.0
newtype PComparator (a :: S -> Type) (s :: S)
    = PComparator (Term s (a :--> a :--> POrdering))
    deriving stock
        ( -- | @since 3.4.0
          Generic
        )
    deriving anyclass
        ( -- | @since 3.4.0
          PlutusType
        )

-- | @since 3.4.0
instance DerivePlutusType (PComparator a) where
    type DPTStrat _ = PlutusTypeNewtype

{- | Given a type with a 'POrd' instance, construct a 'PComparator' from that
 instance.

 @since 3.4.0
-}
pfromOrd ::
    forall (a :: S -> Type) (s :: S).
    (POrd a) =>
    Term s (PComparator a)
pfromOrd = pcon . PComparator $
    phoistAcyclic $
        plam $ \x y ->
            pif (x #== y) (pcon PEQ) (pif (x #< y) (pcon PLT) (pcon PGT))

{- | As 'pfromOrd', but instead uses a projection function into the 'POrd'
 instance to construct the 'PComparator'. Allows other \'-by\' behaviours.

 @since 3.4.0
-}
pfromOrdBy ::
    forall (a :: S -> Type) (b :: S -> Type) (s :: S).
    (POrd a) =>
    Term s ((b :--> a) :--> PComparator b)
pfromOrdBy = phoistAcyclic $
    plam $ \f -> pcon . PComparator $
        plam $ \x y ->
            plet (f # x) $ \fx ->
                plet (f # y) $ \fy ->
                    pif (fx #== fy) (pcon PEQ) (pif (fx #< fy) (pcon PLT) (pcon PGT))

{- | Given a way of \'separating\' a @c@ into an @a@ and a @b@, as well as
 'PComparator's for @a@ and @b@, make a 'PComparator' for @c@.

 = Note

 This uses the fact that 'POrdering' is a 'Semigroup', and assumes that @c@ is
 a tuple of @a@ and @b@ in some sense, and that it should be ordered
 lexicographically on that basis.

 @since 3.4.0
-}
pproductComparator ::
    forall (a :: S -> Type) (b :: S -> Type) (c :: S -> Type) (s :: S).
    Term s ((c :--> PPair a b) :--> PComparator a :--> PComparator b :--> PComparator c)
pproductComparator = phoistAcyclic $
    plam $ \split cmpA cmpB ->
        pmatch cmpA $ \(PComparator fA) ->
            pmatch cmpB $ \(PComparator fB) ->
                pcon . PComparator . plam $ \x y ->
                    pmatch (split # x) $ \(PPair xA xB) ->
                        pmatch (split # y) $ \(PPair yA yB) ->
                            (fA # xA # yA) <> (fB # xB # yB)

{- | Given a way of \'discriminating\' a @c@ into either an @a@ or a @b@, as
 well as 'PComparator's for @a@ and @b@, make a 'PComparator' for @c@.

 = Note

 This assumes that \'@c@s that are @a@s\' should be ordered before \'@c@s that
 are @b@s\'.

 @since 3.4.0
-}
psumComparator ::
    forall (a :: S -> Type) (b :: S -> Type) (c :: S -> Type) (s :: S).
    Term s ((c :--> PEither a b) :--> PComparator a :--> PComparator b :--> PComparator c)
psumComparator = phoistAcyclic $
    plam $ \discriminate cmpA cmpB ->
        pmatch cmpA $ \(PComparator fA) ->
            pmatch cmpB $ \(PComparator fB) ->
                pcon . PComparator . plam $ \x y ->
                    pmatch (discriminate # x) $ \case
                        PLeft xA -> pmatch (discriminate # y) $ \case
                            PLeft yA -> fA # xA # yA
                            PRight _ -> pcon PLT
                        PRight xB -> pmatch (discriminate # y) $ \case
                            PLeft _ -> pcon PGT
                            PRight yB -> fB # xB # yB

{- | Given a projection from a type to another type which we have a
 'PComparator' for, construct a new 'PComparator'.

 @since 3.4.0
-}
pmapComparator ::
    forall (a :: S -> Type) (b :: S -> Type) (s :: S).
    Term s ((b :--> a) :--> PComparator a :--> PComparator b)
pmapComparator = phoistAcyclic $
    plam $ \f cmp ->
        pmatch cmp $ \(PComparator g) ->
            pcon . PComparator . plam $ \x y ->
                g # (f # x) # (f # y)

{- | Reverses the ordering described by a 'PComparator'.

 @since 3.4.0
-}
preverseComparator ::
    forall (a :: S -> Type) (s :: S).
    Term s (PComparator a :--> PComparator a)
preverseComparator = phoistAcyclic $
    plam $ \cmp ->
        pmatch cmp $ \(PComparator f) ->
            pcon . PComparator . plam $ \x y ->
                pmatch (f # x # y) $ \case
                    PEQ -> pcon PEQ
                    PLT -> pcon PGT
                    PGT -> pcon PLT

{- | \'Runs\' a 'PComparator'.

 @since 3.4.0
-}
pcompareBy ::
    forall (a :: S -> Type) (s :: S).
    Term s (PComparator a :--> a :--> a :--> POrdering)
pcompareBy = phoistAcyclic $
    plam $ \cmp x y ->
        pmatch cmp $ \(PComparator f) -> f # x # y

{- | Uses a 'PComparator' for an equality check.

 @since 3.4.0
-}
pequateBy ::
    forall (a :: S -> Type) (s :: S).
    Term s (PComparator a :--> a :--> a :--> PBool)
pequateBy = phoistAcyclic $
    plam $ \cmp x y ->
        pmatch cmp $ \(PComparator f) -> pcon PEQ #== (f # x # y)

-- Helpers

pmergeAll ::
    forall (a :: S -> Type) (ell :: (S -> Type) -> S -> Type) (s :: S).
    (PElemConstraint ell a, PElemConstraint ell (ell a), PListLike ell) =>
    Term s (PComparator a :--> ell (ell a) :--> ell a)
pmergeAll = phoistAcyclic $
    pfix #$ plam $ \self cmp xss ->
        pmatch (PList.puncons # xss) $ \case
            PNothing -> pnil
            PJust xss' -> pmatch xss' $ \(PPair h t) ->
                pmatch (PList.puncons # t) $ \case
                    PNothing -> h
                    PJust _ -> self # cmp #$ go # cmp # t
  where
    go ::
        forall (s' :: S).
        Term s' (PComparator a :--> ell (ell a) :--> ell (ell a))
    go = phoistAcyclic $
        pfix #$ plam $ \self cmp xss ->
            pmatch (PList.puncons # xss) $ \case
                PNothing -> pnil
                PJust xss' -> pmatch xss' $ \(PPair h t) ->
                    pmatch (PList.puncons # t) $ \case
                        PNothing -> xss
                        PJust xss'' -> pmatch xss'' $ \(PPair h' t') ->
                            pcons # (pmerge # cmp # h # h') # (self # cmp # t')

pmerge ::
    forall (a :: S -> Type) (ell :: (S -> Type) -> S -> Type) (s :: S).
    (PElemConstraint ell a, PListLike ell) =>
    Term s (PComparator a :--> ell a :--> ell a :--> ell a)
pmerge = phoistAcyclic $
    pfix #$ plam $ \self cmp xs ys ->
        pmatch (PList.puncons # xs) $ \case
            -- Exhausted xs, yield ys as-is.
            PNothing -> ys
            PJust xs' -> pmatch (PList.puncons # ys) $ \case
                -- Exhausted ys, yield xs as-is.
                PNothing -> xs
                PJust ys' -> pmatch xs' $ \(PPair leftH leftT) ->
                    pmatch ys' $ \(PPair rightH rightT) ->
                        pmatch (pcompareBy # cmp # leftH # rightH) $ \case
                            -- Right before left.
                            PGT -> pcons # rightH #$ pcons # leftH # (self # cmp # leftT # rightT)
                            -- Left before right.
                            _ -> pcons # leftH #$ pcons # rightH # (self # cmp # leftT # rightT)

pmergeStart_2_3 ::
    forall (a :: S -> Type) (ell :: (S -> Type) -> S -> Type) (s :: S).
    (PElemConstraint ell a, PListLike ell, PElemConstraint ell (ell a)) =>
    Term s (PComparator a :--> ell a :--> ell (ell a))
pmergeStart_2_3 = phoistAcyclic $
    pfix #$ plam $ \self cmp ->
        pmatchList pnil $ \_0 ->
            pmatchList (plist [psingletonUnhoisted _0]) $ \_1 ->
                pmatchList (plist [psort2 cmp _0 _1]) $ \_2 ->
                    pmatchList (plist [psort3 cmp _0 _1 _2]) $ \_3 rest ->
                        pcons # psort4 cmp _0 _1 _2 _3 #$ self # cmp # rest
  where
    psort2 ::
        forall (s' :: S).
        Term s' (PComparator a) ->
        Term s' a ->
        Term s' a ->
        Term s' (ell a)
    psort2 cmp _0 _1 = pswap cmp _0 _1 $
        \_0 _1 -> plist [_0, _1]
    psort3 ::
        forall (s' :: S).
        Term s' (PComparator a) ->
        Term s' a ->
        Term s' a ->
        Term s' a ->
        Term s' (ell a)
    psort3 cmp _0 _1 _2 = pswap cmp _0 _2 $
        \_0 _2 -> pswap cmp _0 _1 $
            \_0 _1 -> pswap cmp _1 _2 $
                \_1 _2 -> plist [_0, _1, _2]
    psort4 ::
        forall (s' :: S).
        Term s' (PComparator a) ->
        Term s' a ->
        Term s' a ->
        Term s' a ->
        Term s' a ->
        Term s' (ell a)
    psort4 cmp _0 _1 _2 _3 = pswap cmp _0 _2 $
        \_0 _2 -> pswap cmp _1 _3 $
            \_1 _3 -> pswap cmp _0 _1 $
                \_0 _1 -> pswap cmp _2 _3 $
                    \_2 _3 -> pswap cmp _1 _2 $
                        \_1 _2 -> plist [_0, _1, _2, _3]
    pswap ::
        forall (r :: S -> Type) (s' :: S).
        Term s' (PComparator a) ->
        Term s' a ->
        Term s' a ->
        (Term s' a -> Term s' a -> Term s' r) ->
        Term s' r
    pswap cmp x y cont = pmatch (pcompareBy # cmp # x # y) $ \case
        PGT -> cont y x
        _ -> cont x y
