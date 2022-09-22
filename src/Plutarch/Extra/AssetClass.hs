{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{- | Provides Data and Scott encoded  asset class types and utility
  functions.
-}
module Plutarch.Extra.AssetClass (
    -- * AssetClass - Hask
    AssetClass (AssetClass, symbol, name),
    assetClassValue,

    -- * AssetClass - Plutarch
    PAssetClass (PAssetClass, psymbol, pname),
    adaSymbolData,
    isAdaClass,
    adaClass,
    padaClass,
    emptyTokenNameData,
    pcoerceCls,
    psymbolAssetClass,
    pconstantCls,

    -- * AssetClassData - Hask
    AssetClassData (AssetClassData, symbol, name),

    -- * AssetClassData - Plutarch
    PAssetClassData (PAssetClassData),

    -- * Scott <-> Data conversions
    toScottEncoding,
    ptoScottEncoding,
    fromScottEncoding,
    pfromScottEncoding,
    pviaScottEncoding,
) where

import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import qualified Data.Aeson as Aeson
import Data.Tagged (Tagged, untag)
import GHC.TypeLits (Symbol)
import qualified Generics.SOP as SOP
import Plutarch.Api.V1 (
    PCurrencySymbol,
    PTokenName,
 )
import Plutarch.DataRepr (PDataFields)
import Plutarch.Extra.IsData (
    DerivePConstantViaDataList (DerivePConstantViaDataList),
    ProductIsData (ProductIsData),
 )
import Plutarch.Extra.Record (mkRecordConstr, (.&), (.=))
import Plutarch.Lift (
    PConstantDecl,
    PUnsafeLiftDecl (PLifted),
 )
import Plutarch.Orphans ()
import Plutarch.Unsafe (punsafeCoerce)
import PlutusLedgerApi.V1.Value (CurrencySymbol, TokenName)
import qualified PlutusLedgerApi.V1.Value as Value
import qualified PlutusTx

--------------------------------------------------------------------------------
-- AssetClass & Variants

{- | A version of 'PlutusTx.AssetClass', with a tag for currency.

 @since 3.8.0
-}
data AssetClass (tag :: Symbol) = AssetClass
    { symbol :: CurrencySymbol
    -- ^ @since 3.8.0
    , name :: TokenName
    -- ^ @since 3.8.0
    }
    deriving stock
        ( -- | @since 3.8.0
          Eq
        , -- | @since 3.8.0
          Ord
        , -- | @since 3.8.0
          Show
        , -- | @since 3.8.0
          Generic
        )
    deriving anyclass
        ( -- | @since 3.8.0
          ToJSON
        , -- | @since 3.8.0
          FromJSON
        , -- | @since 3.8.0
          FromJSONKey
        , -- | @since 3.8.0
          ToJSONKey
        )

{- | A Scott-encoded Plutarch equivalent to 'AssetClass'.

 @since 3.8.0
-}
data PAssetClass (unit :: Symbol) (s :: S) = PAssetClass
    { psymbol :: Term s (PAsData PCurrencySymbol)
    -- ^ @since 3.8.0
    , pname :: Term s (PAsData PTokenName)
    -- ^ @since 3.8.0
    }
    deriving stock
        ( -- | @since 3.8.0
          Generic
        )
    deriving anyclass
        ( -- | @since 3.8.0
          PEq
        , -- | @since 3.8.0
          PlutusType
        )

-- | @since 3.8.0
instance DerivePlutusType (PAssetClass unit) where
    type DPTStrat _ = PlutusTypeScott

-- | @since 3.8.0
pconstantCls ::
    forall (unit :: Symbol) (s :: S).
    AssetClass unit ->
    Term s (PAssetClass unit)
pconstantCls (AssetClass sym tk) =
    pcon $
        PAssetClass (pconstantData sym) (pconstantData tk)

{- | Coerce the unit tag of a 'PAssetClass'.
 @since 3.8.0
-}
pcoerceCls ::
    forall (b :: Symbol) (a :: Symbol) (s :: S).
    Term s (PAssetClass a) ->
    Term s (PAssetClass b)
pcoerceCls = punsafeCoerce

{- | Construct a 'PAssetClass' with empty 'pname'.
 @since 3.8.0
-}
psymbolAssetClass ::
    forall (unit :: Symbol) (s :: S).
    Term s (PAsData PCurrencySymbol) ->
    PAssetClass unit s
psymbolAssetClass sym = PAssetClass sym emptyTokenNameData

--------------------------------------------------------------------------------
-- Simple Helpers

{- | Check whether an 'AssetClass' corresponds to Ada.

 @since 3.8.0
-}
isAdaClass :: forall (tag :: Symbol). AssetClass tag -> Bool
isAdaClass (AssetClass s n) = s == s' && n == n'
  where
    (AssetClass s' n') = adaClass

{- | The 'PCurrencySymbol' for Ada, corresponding to an empty string.

 @since 3.8.0
-}
adaSymbolData :: forall (s :: S). Term s (PAsData PCurrencySymbol)
adaSymbolData = pconstantData ""

{- | The 'AssetClass' for Ada, corresponding to an empty currency symbol and
 token name.

 @since 3.8.0
-}
adaClass :: AssetClass "Ada"
adaClass = AssetClass "" ""

{- | Plutarch equivalent for 'adaClass'.

 @since 3.8.0
-}
padaClass :: forall (s :: S). Term s (PAssetClass "Ada")
padaClass = pconstantCls adaClass

{- | The empty 'PTokenName'

 @since 3.8.0
-}
emptyTokenNameData :: forall (s :: S). Term s (PAsData PTokenName)
emptyTokenNameData = pconstantData ""

----------------------------------------
-- Data-Encoded version

{- | A 'PlutusTx.Data'-encoded version of 'AssetClass', without the currency
 tag.

 @since 3.8.0
-}
data AssetClassData = AssetClassData
    { symbol :: CurrencySymbol
    -- ^ @since 3.8.0
    , name :: TokenName
    -- ^ @since 3.8.0
    }
    deriving stock
        ( -- | @since 3.8.0
          Eq
        , -- | @since 3.8.0
          Ord
        , -- | @since 3.8.0
          Show
        , -- | @since 3.8.0
          Generic
        )
    deriving anyclass
        ( -- | @since 3.8.0
          Aeson.ToJSON
        , -- | @since 3.8.0
          Aeson.FromJSON
        , -- | @since 3.8.0
          Aeson.FromJSONKey
        , -- | @since 3.8.0
          Aeson.ToJSONKey
        , -- | @since 3.8.0
          SOP.Generic
        )
    deriving
        ( -- | @since 3.8.0
          PlutusTx.ToData
        , -- | @since 3.8.0
          PlutusTx.FromData
        )
        via Plutarch.Extra.IsData.ProductIsData AssetClassData
    deriving
        ( -- | @since 3.8.0
          Plutarch.Lift.PConstantDecl
        )
        via ( Plutarch.Extra.IsData.DerivePConstantViaDataList
                AssetClassData
                PAssetClassData
            )

{- | Plutarch equivalent of 'AssetClassData'.

 @since 3.8.0
-}
newtype PAssetClassData (s :: S)
    = PAssetClassData
        ( Term
            s
            ( PDataRecord
                '[ "symbol" ':= PCurrencySymbol
                 , "name" ':= PTokenName
                 ]
            )
        )
    deriving stock
        ( -- | @since 3.8.0
          Generic
        )
    deriving anyclass
        ( -- | @since 3.8.0
          PlutusType
        , -- | @since 3.8.0
          PEq
        , -- | @since 3.8.0
          PIsData
        , -- | @since 3.8.0
          PDataFields
        , -- | @since 3.8.0
          PShow
        )

-- | @since 3.8.0
instance DerivePlutusType PAssetClassData where
    type DPTStrat _ = PlutusTypeNewtype

-- | @since 3.8.0
instance Plutarch.Lift.PUnsafeLiftDecl PAssetClassData where
    type PLifted PAssetClassData = AssetClassData

{- | Convert from 'AssetClassData' to 'AssetClass'.

 @since 3.8.0
-}
toScottEncoding :: forall (tag :: Symbol). AssetClassData -> AssetClass tag
toScottEncoding (AssetClassData sym tk) = AssetClass sym tk

{- | Convert from 'AssetClass' to 'AssetClassData'.

 @since 3.8.0
-}
fromScottEncoding :: forall (tag :: Symbol). AssetClass tag -> AssetClassData
fromScottEncoding (AssetClass sym tk) = AssetClassData sym tk

{- | Convert from 'PAssetClassData' to 'PAssetClass'.

 @since 3.8.0
-}
ptoScottEncoding ::
    forall (tag :: Symbol) (s :: S).
    Term
        s
        ( PAsData PAssetClassData
            :--> PAssetClass tag
        )
ptoScottEncoding = phoistAcyclic $
    plam $ \cls ->
        pletFields @["symbol", "name"] (pto cls) $
            \cls' ->
                pcon $
                    PAssetClass
                        (getField @"symbol" cls')
                        (getField @"name" cls')

{- | Convert from 'PAssetClass' to 'PAssetClassData'.

 @since 3.8.0
-}
pfromScottEncoding ::
    forall (tag :: Symbol) (s :: S).
    Term
        s
        ( PAssetClass tag
            :--> PAsData PAssetClassData
        )
pfromScottEncoding = phoistAcyclic $
    plam $ \cls -> pmatch cls $
        \(PAssetClass sym tk) ->
            pdata $
                mkRecordConstr
                    PAssetClassData
                    ( #symbol .= sym
                        .& #name .= tk
                    )

{- | Wrap a function using the Scott-encoded 'PAssetClass' to one using the
 'PlutusTx.Data'-encoded version.

 @since 3.8.0
-}
pviaScottEncoding ::
    forall (tag :: Symbol) (a :: PType).
    ClosedTerm (PAssetClass tag :--> a) ->
    ClosedTerm (PAsData PAssetClassData :--> a)
pviaScottEncoding fn = phoistAcyclic $
    plam $ \cls ->
        fn #$ ptoScottEncoding # cls

{- | Version of 'assetClassValue' for tagged 'AssetClass' and 'Tagged'.

 @since 3.8.0
-}
assetClassValue ::
    forall (unit :: Symbol).
    AssetClass unit ->
    Tagged unit Integer ->
    Value.Value
assetClassValue (AssetClass sym tk) q = Value.singleton sym tk $ untag q
