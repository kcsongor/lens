{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE LiberalTypeSynonyms #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens
-- Copyright   :  (C) 2012 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  Rank2Types
--
-- This package provides lens families, setters, getters, traversals and folds that
-- can all be composed automatically with each other (and other lenses from
-- other van Laarhoven lens libraries) using @(.)@ from Prelude, while
-- reducing the complexity of the API.
--
-- For a longer description and motivation of why you should care about lens families,
-- see <http://comonad.com/reader/2012/mirrored-lenses/>.
--
-- Note: If you merely want your library to /provide/ lenses you may not
-- have to actually import /any/ lens library. For, say, a
-- @'Simple' 'Lens' Bar Foo@, just export a function with the signature:
--
-- > foo :: Functor f => (Foo -> f Foo) -> Bar -> f Bar
--
-- and then you can compose it with other lenses with @(.)@ without needing
-- anything from this library at all.
--
-- Usage:
--
-- You can derive lenses automatically for many data types:
--
-- > import Control.Lens.TH
-- > data Foo a = Foo { _fooArgs :: [String], _fooValue :: a }
-- > makeLenses ''Foo
--
-- This defines the following lenses:
--
-- > fooArgs :: Simple Lens (Foo a) [String]
-- > fooValue :: Lens (Foo a) (Foo b) a b
--
-- The combinators here have unusually specific type signatures, so for
-- particularly tricky ones, I've tried to list the simpler type signatures
-- you might want to pretend the combinators have.
--
----------------------------------------------------------------------------
module Control.Lens
  (
  -- * Lenses
    Lens
  , LensLike
  , Traversal
  , Simple
  , SimpleLens
  , SimpleTraversal
  , SimpleLensLike

  -- ** Constructing Lenses
  , lens
  , iso

  -- * Traversing and Lensing
  , (%%~), (%%=)
  , Focus(..)
  , traverseOf, forOf, sequenceAOf
  , mapMOf, forMOf, sequenceOf
  , transposeOf
  , mapAccumLOf, mapAccumROf
  , scanr1Of, scanl1Of

  -- ** Common Lenses
  , _1, _2
  , identity
  , resultAt

  -- * Setters
  , Setter
  , SimpleSetter
  , sets
  , mapped

  -- ** Setting Values
  , adjust
  , set
  , (^~), (+~), (-~), (*~), (//~), (||~), (&&~), (%~), (<>~)

  -- ** Setting State
  , (^=), (+=), (-=), (*=), (//=), (||=), (&&=), (%=), (<>=)

  -- * Getters and Folds
  , Getter
  , Fold
  , Getting
  , to
  , folding
  , folded
  , filtered
  , reversed
  , takingWhile
  , droppingWhile
  , view, views
  , (^.), (^$)
  , use, uses

  -- ** Getting and Folding
  , foldMapOf, foldOf
  , foldrOf, foldlOf
  , toListOf
  , anyOf, allOf
  , andOf, orOf
  , productOf, sumOf
  , traverseOf_, forOf_, sequenceAOf_
  , mapMOf_, forMOf_, sequenceOf_
  , asumOf, msumOf
  , concatMapOf, concatOf
  , elemOf, notElemOf
  , lengthOf
  , nullOf
  , headOf, lastOf
  , maximumOf, minimumOf
  , maximumByOf, minimumByOf
  , findOf
  , foldrOf', foldlOf'
  , foldr1Of, foldl1Of
  , foldrMOf, foldlMOf

  -- * Common Traversals
  , Traversable(..)
  , traverseNothing
  , traverseLeft
  , traverseRight
  , traverseValue

  -- * Transforming Traversals
  , backwards

  -- * Cloning Lenses
  , clone
  ) where

import Control.Applicative              as Applicative
import Control.Lens.Internal
import Control.Monad
import Control.Monad.State.Class        as State
import Control.Monad.Trans.State.Lazy   as Lazy
import Control.Monad.Trans.State.Strict as Strict
import Control.Monad.Trans.Reader
import Data.Foldable                    as Foldable
import Data.Functor.Identity
import Data.Maybe
import Data.Monoid
import Data.Traversable

infixl 8 ^.
infixr 4 ^~, +~, *~, -~, //~, &&~, ||~, %~, <>~, %%~
infix  4 ^=, +=, *=, -=, //=, &&=, ||=, %=, <>=, %%=
infixr 0 ^$

--------------------------
-- Lenses
--------------------------

-- | A 'Lens' is actually a lens family as described in <http://comonad.com/reader/2012/mirrored-lenses/>.
--
-- With great power comes great responsibility and a 'Lens' is subject to the three common sense lens laws:
--
-- 1) You get back what you put in:
--
-- > view l (set l b a)  = b
--
-- 2) Putting back what you got doesn't change anything:
--
-- > set l (view l a) a  = a
--
-- 3) Setting twice is the same as setting once:
--
-- > set l c (set l b a) = set l c a
--
-- These laws are strong enough that the 4 type parameters of a 'Lens' cannot vary fully independently. For more on
-- how they interact, read the "Why is it a Lens Family?" section of <http://comonad.com/reader/2012/mirrored-lenses/>.
--
-- Every 'Lens' can be used directly as a 'Getter', 'Setter', 'Fold' or 'Traversal'.
--
-- > identity :: Lens (Identity a) (Identity b) a b
-- > identity f (Identity a) = Identity <$> f a
--
-- > type Lens = forall f. Functor f => LensLike f a b c d
type Lens a b c d = forall f. Functor f => (c -> f d) -> a -> f b

------------------------------------------------------------------------------
-- Traversals
------------------------------------------------------------------------------

-- | A 'Traversal' can be used directly as a 'Setter' or a 'Fold' (but not as a 'Lens') and provides
-- the ability to both read and update multiple fields, subject to some relatively weak 'Traversal' laws.
--
-- These have also been known as multilenses, but they have the signature and spirit of
--
-- > traverse :: Traversable f => Traversal (f a) (f b) a b
--
-- and the more evocative name suggests their application.
--
-- Most of the time the 'Traversal' you will want to use is just 'traverse', but you can also pass any
-- 'Lens' -- as a Traversal, and composition of a 'Traversal' (or 'Lens') with a 'Traversal' (or 'Lens')
-- using (.) forms a 'Traversal'.
type Traversal a b c d = forall f. Applicative f => (c -> f d) -> a -> f b

-- | A @'Simple' 'Lens'@, @'Simple' 'Traversal'@, ... can be used instead of a 'Lens','Traversal', ...
-- whenever the type variables don't change upon setting a value.
--
-- > imaginary :: Simple Lens (Complex a) a
-- > traverseHead :: Simple Traversal [a] a
--
-- Note: To use this alias in your own code with @'LensLike' f@ or @Setter@, you may have to turn on
-- @LiberalTypeSynonyms@.
type Simple f a b = f a a b b

-- | > type SimpleTraversal = Simple Traversal
type SimpleTraversal a b = Traversal a a b b

-- | > type SimpleLens = Simple Lens
type SimpleLens a b = Lens a a b b

-- | > type SimpleLensLike f = Simple (LensLike f)
type SimpleLensLike f a b = LensLike f a a b b

--------------------------
-- Constructing Lenses
--------------------------

-- | Build a 'Lens' from a getter and a setter.
--
-- > lens :: Functor f => (a -> c) -> (a -> d -> b) -> (c -> f d) -> a -> f b
lens :: (a -> c) -> (a -> d -> b) -> Lens a b c d
lens ac adb cfd a = adb a <$> cfd (ac a)
{-# INLINE lens #-}

-- | Built a 'Lens' from an isomorphism family
--
-- > iso :: Functor f => (a -> c) -> (d -> b) -> (c -> f d) -> a -> f b
iso :: (a -> c) -> (d -> b) -> Lens a b c d
iso ac db cfd a = db <$> cfd (ac a)
{-# INLINE iso #-}

--------------------------
-- LensLike
--------------------------

-- |
-- Many combinators that accept a 'Lens' can also accept a 'Traversal' in limited situations.
--
-- They do so by specializing the type of 'Functor' that they require of the caller.
--
-- If a function accepts a @'LensLike' f a b c d@ for some 'Functor' @f@, then they may be passed a 'Lens'.
--
-- Further, if @f@ is an 'Applicative', they may also be passed a 'Traversal'.
type LensLike f a b c d = (c -> f d) -> a -> f b

-- | ('%%~') can be used in one of two scenarios:
--
-- When applied to a 'Lens', it can edit the target of the 'Lens' in a structure, extracting a
-- supplemental result, and the new structure.
--
-- When applied to a 'Traversal', it can edit the targets of the 'Traversals', extracting a
-- supplemental monoidal summary of its actions.
--
-- For all that the definition of this combinator is just:
--
-- > (%%~) = id
--
-- It may be beneficial to think about it as if it had these more restrictive types, however:
--
-- > (%%~) ::             Lens a b c d      -> (c -> (e, d)) -> a -> (e, b)
-- > (%%~) :: Monoid m => Traversal a b c d -> (c -> (m, d)) -> a -> (m, b)
(%%~) :: LensLike ((,) e) a b c d -> (c -> (e, d)) -> a -> (e, b)
(%%~) = id
{-# INLINE (%%~) #-}

-- | Modify the target of a 'Lens' in the current state returning some extra information of @c@ or
-- modify all targets of a 'Traversal' in the current state, extracting extra information of type @c@
-- and return a monoidal summary of the changes.
--
-- > (%%=) = (state.)
--
-- It may be useful to think of ('%%='), instead, as having either of the following more restricted
-- type signatures:
--
-- > (%%=) :: MonadState a m             => Lens a a c d      -> (c -> (e, d) -> m e
-- > (%%=) :: (MonadState a m, Monoid e) => Traversal a a c d -> (c -> (e, d) -> m e
(%%=) :: MonadState a m => LensLike ((,) e) a a c d -> (c -> (e, d)) -> m e
l %%= f = State.state (l f)
{-# INLINE (%%=) #-}

-- | This class allows us to use 'focus' on a number of different monad transformers.
class Focus st where
  -- | Run a monadic action in a larger context than it was defined in, using a 'Simple' 'Lens' or 'Simple' 'Traversal'.
  --
  -- This is commonly used to lift actions in a simpler state monad into a state monad with a larger state type.
  --
  -- When applied to a 'Simple 'Traversal' over multiple values, the actions for each target are executed sequentially
  -- and the results are aggregated monoidally
  -- and a monoidal summary
  -- of the result is given.
  --
  -- > focus :: Monad m             => Simple Lens a b      -> st b m c -> st a m c
  -- > focus :: (Monad m, Monoid c) => Simple Traversal a b -> st b m c -> st a m c
  focus :: Monad m => LensLike (Focusing m c) a a b b -> st b m c -> st a m c

  -- | Like 'focus', but discarding any accumulated results as you go.
  --
  -- > focus_ :: Monad m             => Simple Lens a b      -> st b m c -> st a m ()
  -- > focus_ :: (Monad m, Monoid c) => Simple Traversal a b -> st b m c -> st a m ()
  focus_ :: Monad m => LensLike (Focusing m ()) a a b b -> st b m c -> st a m ()

  -- | A much more limited version of 'focus' that can work with a 'Setter'.
  setFocus :: Simple Setter a b -> st b Identity c -> st a Identity ()

skip :: a -> ()
skip _ = ()
{-# INLINE skip #-}

instance Focus Strict.StateT where
  focus l m = Strict.StateT $ unfocusing . l (Focusing . Strict.runStateT m)
  {-# INLINE focus #-}
  focus_ l m = Strict.StateT $ unfocusing . l (Focusing . Strict.runStateT (liftM skip m))
  {-# INLINE focus_ #-}
  setFocus l m = Strict.state $ (,) () . runIdentity . l (Identity . snd . Strict.runState m)

instance Focus Lazy.StateT where
  focus l m = Lazy.StateT $ unfocusing . l (Focusing . Lazy.runStateT m)
  {-# INLINE focus #-}
  focus_ l m = Lazy.StateT $ unfocusing . l (Focusing . Lazy.runStateT (liftM skip m))
  {-# INLINE focus_ #-}
  setFocus l m = Lazy.state $ (,) () . runIdentity . l (Identity . snd . Lazy.runState m)

instance Focus ReaderT where
  --focus l m = ReaderT $ \a -> liftM fst $ unfocusing $ l (\b -> Focusing $ (\c -> (c,b)) `liftM` runReaderT m b) a
  focus l m = ReaderT $ liftM fst . unfocusing . l (\b -> Focusing $ (\c -> (c,b)) `liftM` runReaderT m b)
  {-# INLINE focus #-}
  focus_ l m = ReaderT $ \a -> liftM skip $ unfocusing $ l (\b -> Focusing $ (\_ -> ((),b)) `liftM` runReaderT m b) a
  {-# INLINE focus_ #-}
  setFocus _ _ = return () -- BOOORING

--------------------------
-- Traversal Combinators
--------------------------

-- |
-- Map each element of a structure targeted by a Lens or Traversal,
-- evaluate these actions from left to right, and collect the results.
--
-- > traverseOf = id
--
-- > traverse = traverseOf traverse
--
-- > traverseOf :: Lens a b c d      -> (c -> f d) -> a -> f b
-- > traverseOf :: Traversal a b c d -> (c -> f d) -> a -> f b
traverseOf :: LensLike f a b c d -> (c -> f d) -> a -> f b
traverseOf = id

-- |
--
-- > forOf = flip
-- > forOf l = flip (traverseOf l)
--
-- > for = forOf traverse
forOf :: LensLike f a b c d -> a -> (c -> f d) -> f b
forOf = flip

-- |
-- Evaluate each action in the structure from left to right, and collect
-- the results.
--
-- > sequenceA = sequenceAOf traverse
-- > sequenceAOf l = traverseOf l id
-- > sequenceAOf l = l id
--
-- > sequenceAOf ::                  Lens a b (f c) c -> a -> f b
-- > sequenceAOf :: Applicative f => Traversal a b (f c) c -> a -> f b
sequenceAOf :: LensLike f a b (f c) c -> a -> f b
sequenceAOf l = l id
{-# INLINE sequenceAOf #-}

-- | Map each element of a structure targeted by a lens to a monadic action,
-- evaluate these actions from left to right, and collect the results.
--
-- > mapM = mapMOf traverse
--
-- > mapMOf ::            Lens a b c d      -> (c -> m d) -> a -> m b
-- > mapMOf :: Monad m => Traversal a b c d -> (c -> m d) -> a -> m b
mapMOf :: LensLike (WrappedMonad m) a b c d -> (c -> m d) -> a -> m b
mapMOf l cmd = unwrapMonad . l (WrapMonad . cmd)
{-# INLINE mapMOf #-}

-- |
-- > forM = forMOf traverse
-- > forMOf l = flip (mapMOf l)
--
-- > forMOf ::            Lens a b c d -> a -> (c -> m d) -> m b
-- > forMOf :: Monad m => Lens a b c d -> a -> (c -> m d) -> m b
forMOf :: LensLike (WrappedMonad m) a b c d -> a -> (c -> m d) -> m b
forMOf l a cmd = unwrapMonad (l (WrapMonad . cmd) a)
{-# INLINE forMOf #-}

-- |
-- > sequence = sequenceOf traverse
-- > sequenceOf l = mapMOf l id
-- > sequenceOf l = unwrapMonad . l WrapMonad
--
-- > sequenceOf ::            Lens a b (m c) c      -> a -> m b
-- > sequenceOf :: Monad m => Traversal a b (m c) c -> a -> m b
sequenceOf :: LensLike (WrappedMonad m) a b (m c) c -> a -> m b
sequenceOf l = unwrapMonad . l WrapMonad
{-# INLINE sequenceOf #-}

-- | This generalizes 'Data.List.transpose' to an arbitrary 'Traversal'.
--
-- > transpose = transposeOf traverse
--
-- > ghci> transposeOf traverse [[1,2,3],[4,5,6]]
-- > [[1,4],[2,5],[3,6]]
--
-- Since every 'Lens' is a Traversal, we can use this as a form of
-- monadic strength.
--
-- > transposeOf _2 :: (b, [a]) -> [(b, a)]
transposeOf :: LensLike ZipList a b [c] c -> a -> [b]
transposeOf l = getZipList . l ZipList
{-# INLINE transposeOf #-}

-- | Generalizes 'Data.Traversable.mapAccumR' to an arbitrary 'Traversal'.
--
-- > mapAccumR = mapAccumROf traverse
--
-- 'mapAccumROf' accumulates state from right to left.
--
-- > mapAccumROf :: Lens a b c d      -> (s -> c -> (s, d)) -> s -> a -> (s, b)
-- > mapAccumROf :: Traversal a b c d -> (s -> c -> (s, d)) -> s -> a -> (s, b)
mapAccumROf :: LensLike (Lazy.State s) a b c d -> (s -> c -> (s, d)) -> s -> a -> (s, b)
mapAccumROf l f s0 a = swap (Lazy.runState (l (\c -> State.state (\s -> swap (f s c))) a) s0)
{-# INLINE mapAccumROf #-}

-- | Generalized 'Data.Traversable.mapAccumL' to an arbitrary 'Traversal'.
--
-- > mapAccumL = mapAccumLOf traverse
--
-- 'mapAccumLOf' accumulates state from left to right.
--
-- > mapAccumLOf :: Lens a b c d      -> (s -> c -> (s, d)) -> s -> a -> (s, b)
-- > mapAccumLOf :: Traversal a b c d -> (s -> c -> (s, d)) -> s -> a -> (s, b)
mapAccumLOf :: LensLike (Backwards (Lazy.State s)) a b c d -> (s -> c -> (s, d)) -> s -> a -> (s, b)
mapAccumLOf l = mapAccumROf (backwards l)
{-# INLINE mapAccumLOf #-}

swap :: (a,b) -> (b,a)
swap (a,b) = (b,a)
{-# INLINE swap #-}

-- | Permit the use of 'scanr1' over an arbitrary 'Traversal' or 'Lens'.
--
-- > scanr1 = scanr1Of traverse
--
-- > scanr1Of :: Lens a b c c      -> (c -> c -> c) -> a -> b
-- > scanr1Of :: Traversal a b c c -> (c -> c -> c) -> a -> b
scanr1Of :: LensLike (Lazy.State (Maybe c)) a b c c -> (c -> c -> c) -> a -> b
scanr1Of l f = snd . mapAccumROf l step Nothing where
  step Nothing c  = (Just c, c)
  step (Just s) c = (Just r, r) where r = f c s
{-# INLINE scanr1Of #-}

-- | Permit the use of 'scanl1' over an arbitrary 'Traversal' or 'Lens'.
--
-- > scanl1 = scanl1Of traverse
--
-- > scanr1Of :: Lens a b c c      -> (c -> c -> c) -> a -> b
-- > scanr1Of :: Traversal a b c c -> (c -> c -> c) -> a -> b
scanl1Of :: LensLike (Backwards (Lazy.State (Maybe c))) a b c c -> (c -> c -> c) -> a -> b
scanl1Of l f = snd . mapAccumLOf l step Nothing where
  step Nothing c  = (Just c, c)
  step (Just s) c = (Just r, r) where r = f s c
{-# INLINE scanl1Of #-}

------------------------------------------------------------------------------
-- Setters
------------------------------------------------------------------------------

-- |
-- The only 'Lens'-like law that can apply to a 'Setter' @l@ is that
--
-- > set l c (set l b a) = set l c a
--
-- You can't 'view' a 'Setter' in general, so the other two laws are irrelevant.
--
-- You can compose a 'Setter' with a 'Lens' or a 'Traversal' using @(.)@ from the Prelude
-- and the result is always only a 'Setter' and nothing more.
--
-- > type Setter a b c d = LensLike Identity a b c d
type Setter a b c d = (c -> Identity d) -> a -> Identity b

-- | This alias is supplied for those who don't want to bother using {-# LANGUAGE LiberalTypeSynonyms #-} and 'Simple'.
--
-- > 'SimpleSetter ' = 'Simple' 'Setter'
type SimpleSetter a b = Lens a a b b

-- | This setter can be used to map over all of the values in a 'Functor'.
--
-- > fmap        = adjust mapped
-- > fmapDefault = adjust traverse
-- > (<$)        = set mapped
mapped :: Functor f => Setter (f a) (f b) a b
mapped = sets fmap
{-# INLINE mapped #-}

-- | Build a Setter.
--
-- > sets . adjust = id
-- > adjust . sets = id
sets :: ((c -> d) -> a -> b) -> Setter a b c d
sets f g a = Identity (f (runIdentity . g) a)
{-# INLINE sets #-}

-- | Modify the target of a 'Lens' or all the targets of a 'Setter' or 'Traversal'
-- with a function.
--
-- > fmap        = adjust mapped
-- > fmapDefault = adjust traverse
--
-- > sets . adjust = id
-- > adjust . sets = id
adjust :: Setter a b c d -> (c -> d) -> a -> b
adjust l f = runIdentity . l (Identity . f)
{-# INLINE adjust #-}

-- | Replace the target of a 'Lens' or all of the targets of a 'Setter'
-- or 'Traversal' with a constant value.
--
-- > (<$) = set mapped
set :: Setter a b c d -> d -> a -> b
set l d = runIdentity . l (\_ -> Identity d)
{-# INLINE set #-}

-- | Modifies the target of a 'Lens' or all of the targets of a 'Setter' or
-- 'Traversal' with a user supplied function.
--
-- This is an infix version of 'adjust'
--
-- > fmap f = mapped %~ f
-- > fmapDefault f = traverse %~ f
--
-- > ghci> _2 %~ length $ (1,"hello")
-- > (1,5)
(%~) :: Setter a b c d -> (c -> d) -> a -> b
l %~ f = runIdentity . l (Identity . f)
{-# INLINE (%~) #-}

-- | Replace the target of a 'Lens' or all of the targets of a 'Setter'
-- or 'Traversal' with a constant value.
--
-- This is an infix version of 'set'
--
-- > f <$ a = mapped ^~ f $ a
--
-- > ghci> bitAt 0 ^~ True $ 0
-- > 1
(^~) :: Setter a b c d -> d -> a -> b
l ^~ v = runIdentity . l (Identity . const v)
{-# INLINE (^~) #-}

-- | Increment the target(s) of a numerically valued 'Lens', Setter' or 'Traversal'
--
-- > ghci> _1 +~ 1 $ (1,2)
-- > (2,2)
(+~) :: Num c => Setter a b c c -> c -> a -> b
l +~ n = adjust l (+ n)
{-# INLINE (+~) #-}

-- | Multiply the target(s) of a numerically valued 'Lens', 'Setter' or 'Traversal'
--
-- > ghci> _2 *~ 4 $ (1,2)
-- > (1,8)
(*~) :: Num c => Setter a b c c -> c -> a -> b
l *~ n = adjust l (* n)
{-# INLINE (*~) #-}

-- | Decrement the target(s) of a numerically valued 'Lens', 'Setter' or 'Traversal'
--
-- > ghci> _1 -~ 2 $ (1,2)
-- > (-1,2)
(-~) :: Num c => Setter a b c c -> c -> a -> b
l -~ n = adjust l (subtract n)
{-# INLINE (-~) #-}

-- | Divide the target(s) of a numerically valued 'Lens', 'Setter' or 'Traversal'
(//~) :: Fractional c => Setter a b c c -> c -> a -> b
l //~ n = adjust l (/ n)

-- | Logically '||' the target(s) of a 'Bool'-valued 'Lens' or 'Setter'
(||~):: Setter a b Bool Bool -> Bool -> a -> b
l ||~ n = adjust l (|| n)
{-# INLINE (||~) #-}

-- | Logically '&&' the target(s) of a 'Bool'-valued 'Lens' or 'Setter'
(&&~) :: Setter a b Bool Bool -> Bool -> a -> b
l &&~ n = adjust l (&& n)
{-# INLINE (&&~) #-}

-- | Modify the target of a monoidally valued by 'mappend'ing another value.
(<>~) :: Monoid c => Setter a b c c -> c -> a -> b
l <>~ n = adjust l (<> n)
{-# INLINE (<>~) #-}

---------------
-- Getters
---------------

-- | A 'Getter' describes how to retrieve a single value in a way that can be composed with
-- other lens-like constructions.
--
-- Unlike a 'Lens' a 'Getter' is read-only. Since a 'Getter' cannot be used to write back
-- there are no lens laws that can be applied to it.
--
-- Moreover, a 'Getter' can be used directly as a 'Fold', since it just ignores the 'Monoid'.
--
-- In practice the @b@ and @d@ are left dangling and unused, and as such is no real point in
-- using a @'Simple' 'Getter'@.
--
-- type Getter a b c d = forall z. LensLike (Const z) a b c d
type Getter a b c d = forall z. (c -> Const z d) -> a -> Const z b

-- | Build a 'Getter' from an arbitrary Haskell function.
--
-- > to f . to g = to (g . f)
to :: (a -> c) -> Getter a b c d
to f g a = Const (getConst (g (f a)))
{-# INLINE to #-}

-- |
-- Most 'Getter' combinators are able to be used with both a 'Getter' or a 'Fold' in
-- limited situations, to do so, they need to be monomorphic in what we are going to
-- extract with 'Const'.
--
-- If a function accepts a @Getting r a b c d@, then when @r@ is a Monoid, you can
-- pass a 'Fold' (or 'Traversal'), otherwise you can only pass this a 'Getter' or 'Lens'.
--
-- > type Getting r a b c d = LensLike (Const r) a b c d
type Getting r a b c d = (c -> Const r d) -> a -> Const r b

-------------------------------
-- Getting Values
-------------------------------

-- | View the value pointed to by a 'Getter' or 'Lens' or the result of folding over
-- all the results of a 'Fold' or 'Traversal' that points at a monoidal values.
--
-- It may be useful to think of 'view' as having these more restrictive signatures:
--
-- > view ::             Lens a b c d      -> a -> c
-- > view ::             Getter a b c d    -> a -> c
-- > view :: Monoid m => Fold a b m d      -> a -> m
-- > view :: Monoid m => Traversal a b m d -> a -> m
--
-- > view :: ((c -> Const c d) -> a -> Const c b) -> a -> c
view :: Getting c a b c d -> a -> c
view l a = getConst (l Const a)
{-# INLINE view #-}

-- | View the value of a 'Getter', 'Lens' or the result of folding over the
-- result of mapping the targets of a 'Fold' or 'Traversal'.
--
-- It may be useful to think of 'views' as having these more restrictive signatures:
--
-- > views ::             Getter a b c d    -> (c -> d) -> a -> d
-- > views ::             Lens a b c d      -> (c -> d) -> a -> d
-- > views :: Monoid m => Fold a b c d      -> (c -> m) -> a -> m
-- > views :: Monoid m => Traversal a b c d -> (c -> m) -> a -> m
--
-- > views :: ((c -> Const m d) -> a -> Const m b) -> (c -> m) -> a -> m
views :: Getting m a b c d -> (c -> m) -> a -> m
views l f = getConst . l (Const . f)
{-# INLINE views #-}

-- | View the value pointed to by a 'Getter' or 'Lens' or the result of folding over
-- all the results of a 'Fold' or 'Traversal' that points at a monoidal values.
--
-- This is the same operation as 'view', only infix.
--
-- > (^$) ::             Lens a b c d      -> a -> c
-- > (^$) ::             Getter a b c d    -> a -> c
-- > (^$) :: Monoid m => Fold a b m d      -> a -> m
-- > (^$) :: Monoid m => Traversal a b m d -> a -> m
--
-- > (^$) :: ((c -> Const c d) -> a -> Const c b) -> a -> c
(^$) :: Getting c a b c d -> a -> c
l ^$ a = getConst (l Const a)
{-# INLINE (^$) #-}

-- | View the value pointed to by a 'Getter' or 'Lens' or the result of folding over
-- all the results of a 'Fold' or 'Traversal' that points at a monoidal values.
--
-- This is the same operation as 'view' with the arguments flipped.
--
-- The fixity and semantics are such that subsequent field accesses can be
-- performed with (Prelude..)
--
-- > ghci> ((0, 1 :+ 2), 3)^._1._2.to magnitude
-- > 2.23606797749979
--
-- > (^.) ::             a -> Lens a b c d      -> c
-- > (^.) ::             a -> Getter a b c d    -> c
-- > (^.) :: Monoid m => a -> Fold a b m d      -> m
-- > (^.) :: Monoid m => a -> Traversal a b m d -> m
--
-- > (^.) :: a -> ((c -> Const c d) -> a -> Const c b) -> c
(^.) :: a -> Getting c a b c d -> c
a ^. l = getConst (l Const a)
{-# INLINE (^.) #-}

------------------------------------------------------------------------------
-- Common Lenses
------------------------------------------------------------------------------

-- | This is a lens that can change the value (and type) of the first field of
-- a pair.
--
-- > ghci> (1,2)^._1
-- > 1
--
-- > ghci> _1 +~ "hello" $ (1,2)
-- > ("hello",2)
--
-- > _1 :: Functor f => (a -> f b) -> (a,c) -> f (a,c)
_1 :: Lens (a,c) (b,c) a b
_1 f (a,c) = (\b -> (b,c)) <$> f a
{-# INLINE _1 #-}

-- | As '_1', but for the second field of a pair.
--
-- > anyOf _2 :: (c -> Bool) -> (a, c) -> Bool
-- > traverse._2 :: (Applicative f, Traversable t) => (a -> f b) -> t (c, a) -> f (t (c, b))
-- > foldMapOf (traverse._2) :: (Traversable t, Monoid m) => (c -> m) -> t (b, c) -> m
--
-- > _2 :: Functor f => (a -> f b) -> (c,a) -> f (c,b)
_2 :: Lens (c,a) (c,b) a b
_2 f (c,a) = (,) c <$> f a
{-# INLINE _2 #-}

-- | This lens can be used to access the contents of the Identity monad
identity :: Lens (Identity a) (Identity b) a b
identity f (Identity a) = Identity <$> f a
{-# INLINE identity #-}

-- | This lens can be used to change the result of a function but only where
-- the arguments match the key given.
resultAt :: Eq e => e -> Simple Lens (e -> a) a
resultAt e afa ea = go <$> afa a where
  a = ea e
  go a' e' | e == e'   = a'
           | otherwise = a
{-# INLINE resultAt #-}

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

-- |
-- Use the target of a 'Lens' or 'Getter' in the current state, or use a
-- summary of a 'Fold' or 'Traversal' that points to a monoidal value.
--
-- > use :: MonadState a m             => Getter a b c d    -> m c
-- > use :: MonadState a m             => Lens a b c d      -> m c
-- > use :: (MonadState a m, Monoid c) => Fold a b c d      -> m c
-- > use :: (MonadState a m, Monoid c) => Traversal a b c d -> m c
--
-- > use :: MonadState a m => ((c -> Const c d) -> a -> Const c b) -> m c
use :: MonadState a m => Getting c a b c d -> m c
use l = State.gets (^.l)
{-# INLINE use #-}

-- |
-- Use the target of a 'Lens' or 'Getter' in the current state, or use a
-- summary of a 'Fold' or 'Traversal' that points to a monoidal value.
--
-- > uses :: MonadState a m             => Getter a b c d    -> (c -> e) -> m e
-- > uses :: MonadState a m             => Lens a b c d      -> (c -> e) -> m e
-- > uses :: (MonadState a m, Monoid c) => Fold a b c d      -> (c -> e) -> m e
-- > uses :: (MonadState a m, Monoid c) => Traversal a b c d -> (c -> e) -> m e
--
-- > uses :: MonadState a m => ((c -> Const e d) -> a -> Const e b) -> (c -> e) -> m e
uses :: MonadState a m => Getting e a b c d -> (c -> e) -> m e
uses l f = State.gets (views l f)
{-# INLINE uses #-}

-- | Replace the target of a 'Lens' or all of the targets of a 'Setter' or 'Traversal' in our monadic
-- state with a new value, irrespective of the old.
(^=) :: MonadState a m => Setter a a c d -> d -> m ()
l ^= b = State.modify (l ^~ b)
{-# INLINE (^=) #-}

-- | Map over the target of a 'Lens' or all of the targets of a 'Setter' or 'Traversal in our monadic state.
(%=) :: MonadState a m => Setter a a c d -> (c -> d) -> m ()
l %= f = State.modify (l %~ f)
{-# INLINE (%=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by adding a value
--
-- Example:
--
-- > fresh = do
-- >   id += 1
-- >   access id
(+=) :: (MonadState a m, Num b) => Simple Setter a b -> b -> m ()
l += b = State.modify (l +~ b)
{-# INLINE (+=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by subtracting a value
(-=) :: (MonadState a m, Num b) => Simple Setter a b -> b -> m ()
l -= b = State.modify (l -~ b)
{-# INLINE (-=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by multiplying by value
(*=) :: (MonadState a m, Num b) => Simple Setter a b -> b -> m ()
l *= b = State.modify (l *~ b)
{-# INLINE (*=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by dividing by a value
(//=) ::  (MonadState a m, Fractional b) => Simple Setter a b -> b -> m ()
l //= b = State.modify (l //~ b)
{-# INLINE (//=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by taking their logical '&&' with a value
(&&=):: MonadState a m => Simple Setter a Bool -> Bool -> m ()
l &&= b = State.modify (l &&~ b)
{-# INLINE (&&=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by taking their logical '||' with a value
(||=) :: MonadState a m => Simple Setter a Bool -> Bool -> m ()
l ||= b = State.modify (l ||~ b)
{-# INLINE (||=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Setter' or 'Traversal' by 'mappend'ing a value.
(<>=) :: (MonadState a m, Monoid b) => Simple Setter a b -> b -> m ()
l <>= b = State.modify (l <>~ b)
{-# INLINE (<>=) #-}

--------------------------
-- Folds
--------------------------
-- | A 'Fold' describes how to retrieve multiple values in a way that can be composed
-- with other lens-like constructions.
--
-- A @'Fold' a b c d@ provides a structure with operations very similar to those of the 'Foldable'
-- typeclass, see 'foldMapOf' and the other 'Fold' combinators.
--
-- By convention, if there exists a 'foo' method that expects a @'Foldable' (f c)@, then there should be a
-- 'fooOf' method that takes a @'Fold' a b c d@ and a value of type @a@.
--
-- A 'Getter' is a legal 'Fold' that just ignores the supplied 'Monoid'
--
-- Unlike a 'Traversal' a 'Fold' is read-only. Since a 'Fold' cannot be used to write back
-- there are no lens laws that can be applied to it.
--
-- In practice the @b@ and @d@ are left dangling and unused, and as such is no real point in a @'Simple' 'Fold'@.
--
-- > type Fold a b c d = forall m. Monoid m => Getting m a b c d
type Fold a b c d      = forall m. Monoid m => (c -> Const m d) -> a -> Const m b

-- | Obtain a 'Fold' by lifting an operation that returns a foldable result.
--
-- This can be useful to lift operations from @Data.List@ and elsewhere into a 'Fold'.
folding :: Foldable f => (a -> f c) -> Fold a b c d
folding f g = Const . foldMap (getConst . g) . f
{-# INLINE folding #-}

-- | Obtain a 'Fold' from any 'Foldable'
--
-- > folded = folding id
folded :: Foldable f => Fold (f c) b c d
folded g = Const . foldMap (getConst . g)
{-# INLINE folded #-}

-- | Obtain a 'Fold' by filtering a 'Lens', 'Getter, 'Fold' or 'Traversal'.
filtered :: Monoid m => (c -> Bool) -> Getting m a b c d -> Getting m a b c d
filtered p l f = l (\c -> if p c then f c else Const mempty)
{-# INLINE filtered #-}

-- | Obtain a 'Fold' by reversing the order of traversal for a 'Lens', 'Getter', 'Fold' or 'Traversal'.
--
-- Of course, reversing a 'Fold' or 'Getter' has no effect.
reversed :: Getting (Dual m) a b c d -> Getting m a b c d
reversed l f = Const . getDual . getConst . l (Const .  Dual . getConst . f)
{-# INLINE reversed #-}

--taking :: Int -> Getting (Taking m) a b c d -> Getting m a b c d
--dropping :: Int -> Getting (Dropping m) a b c d -> Getting m a b c d

-- | Obtain a 'Fold' by taking elements from another 'Fold', 'Lens', 'Getter' or 'Traversal' while a predicate holds.
--
-- > takeWhile p = toListOf (takingWhile p folded)
--
-- > ghci> toList (takingWhile (<=3) folded) [1..]
-- > [1,2,3]
takingWhile :: Monoid m => (c -> Bool) -> Getting (Endo m) a b c d -> Getting m a b c d
takingWhile p l f = Const . foldrOf l (\a r -> if p a then getConst (f a) `mappend` r else mempty) mempty
{-# INLINE takingWhile #-}

-- | Obtain a 'Fold' by dropping elements from another 'Fold', 'Lens', 'Getter' or 'Traversal' while a predicate holds.
--
-- > dropWhile p = toListOf (droppingWhile p folded)
--
-- > ghci> toList (dropWhile (<=3) folded) [1..6]
-- > [4,5,6]
droppingWhile :: Monoid m => (c -> Bool) -> Getting (Endo m) a b c d -> Getting m a b c d
droppingWhile p l f = Const . foldrOf l (\a r -> if p a then mempty else mappend r (getConst (f a))) mempty
{-# INLINE droppingWhile #-}

--------------------------
-- Fold/Getter combinators
--------------------------

-- |
-- > foldMap = foldMapOf folded
--
-- > foldMapOf = views
--
-- > foldMapOf ::             Getter a b c d    -> (c -> m) -> a -> m
-- > foldMapOf ::             Lens a b c d      -> (c -> m) -> a -> m
-- > foldMapOf :: Monoid m => Fold a b c d      -> (c -> m) -> a -> m
-- > foldMapOf :: Monoid m => Traversal a b c d -> (c -> m) -> a -> m
foldMapOf :: Getting m a b c d -> (c -> m) -> a -> m
foldMapOf l f = getConst . l (Const . f)
{-# INLINE foldMapOf #-}

-- |
-- > fold = foldOf folded
--
-- > foldOf = view
--
-- > foldOf ::             Getter a b m d    -> a -> m
-- > foldOf ::             Lens a b m d      -> a -> m
-- > foldOf :: Monoid m => Fold a b m d      -> a -> m
-- > foldOf :: Monoid m => Traversal a b m d -> a -> m
foldOf :: Getting m a b m d -> a -> m
foldOf l = getConst . l Const
{-# INLINE foldOf #-}

-- |
-- Right-associative fold of parts of a structure that are viewed through a 'Lens', 'Getter', 'Fold' or 'Traversal'.
--
-- > foldr = foldrOf folded
--
-- > foldrOf :: Getter a b c d    -> (c -> e -> e) -> e -> a -> e
-- > foldrOf :: Lens a b c d      -> (c -> e -> e) -> e -> a -> e
-- > foldrOf :: Fold a b c d      -> (c -> e -> e) -> e -> a -> e
-- > foldrOf :: Traversal a b c d -> (c -> e -> e) -> e -> a -> e
foldrOf :: Getting (Endo e) a b c d -> (c -> e -> e) -> e -> a -> e
foldrOf l f z t = appEndo (foldMapOf l (Endo . f) t) z
{-# INLINE foldrOf #-}

-- |
-- Left-associative fold of the parts of a structure that are viewed through a 'Lens', 'Getter', 'Fold' or 'Traversal'.
--
-- > foldl = foldlOf folded
--
-- > foldlOf :: Getter a b c d    -> (e -> c -> e) -> e -> a -> e
-- > foldlOf :: Lens a b c d      -> (e -> c -> e) -> e -> a -> e
-- > foldlOf :: Fold a b c d      -> (e -> c -> e) -> e -> a -> e
-- > foldlOf :: Traversal a b c d -> (e -> c -> e) -> e -> a -> e
foldlOf :: Getting (Dual (Endo e)) a b c d -> (e -> c -> e) -> e -> a -> e
foldlOf l f z t = appEndo (getDual (foldMapOf l (Dual . Endo . flip f) t)) z
{-# INLINE foldlOf #-}

-- |
-- > toList = toListOf folded
--
-- > toListOf :: Getter a b c d    -> a -> [c]
-- > toListOf :: Lens a b c d      -> a -> [c]
-- > toListOf :: Fold a b c d      -> a -> [c]
-- > toListOf :: Traversal a b c d -> a -> [c]
toListOf :: Getting [c] a b c d -> a -> [c]
toListOf l = foldMapOf l return
{-# INLINE toListOf #-}

-- |
-- > and = andOf folded
--
-- > andOf :: Getter a b Bool d   -> a -> Bool
-- > andOf :: Lens a b Bool d     -> a -> Bool
-- > andOf :: Fold a b Bool d     -> a -> Bool
-- > andOf :: Traversl a b Bool d -> a -> Bool
andOf :: Getting All a b Bool d -> a -> Bool
andOf l = getAll . foldMapOf l All
{-# INLINE andOf #-}

-- |
-- > or = orOf folded
--
-- > orOf :: Getter a b Bool d    -> a -> Bool
-- > orOf :: Lens a b Bool d      -> a -> Bool
-- > orOf :: Fold a b Bool d      -> a -> Bool
-- > orOf :: Traversal a b Bool d -> a -> Bool
orOf :: Getting Any a b Bool d -> a -> Bool
orOf l = getAny . foldMapOf l Any
{-# INLINE orOf #-}

-- |
-- > any = anyOf folded
--
-- > anyOf :: Getter a b c d    -> (c -> Bool) -> a -> Bool
-- > anyOf :: Lens a b c d      -> (c -> Bool) -> a -> Bool
-- > anyOf :: Fold a b c d      -> (c -> Bool) -> a -> Bool
-- > anyOf :: Traversal a b c d -> (c -> Bool) -> a -> Bool
anyOf :: Getting Any a b c d -> (c -> Bool) -> a -> Bool
anyOf l f = getAny . foldMapOf l (Any . f)
{-# INLINE anyOf #-}

-- |
-- > all = allOf folded
--
-- > allOf :: Getter a b c d    -> (c -> Bool) -> a -> Bool
-- > allOf :: Lens a b c d      -> (c -> Bool) -> a -> Bool
-- > allOf :: Fold a b c d      -> (c -> Bool) -> a -> Bool
-- > allOf :: Traversal a b c d -> (c -> Bool) -> a -> Bool
allOf :: Getting All a b c d -> (c -> Bool) -> a -> Bool
allOf l f = getAll . foldMapOf l (All . f)
{-# INLINE allOf #-}

-- |
-- > product = productOf folded
--
-- > productOf ::          Getter a b c d    -> a -> c
-- > productOf ::          Lens a b c d      -> a -> c
-- > productOf :: Num c => Fold a b c d      -> a -> c
-- > productOf :: Num c => Traversal a b c d -> a -> c
productOf :: Getting (Product c) a b c d -> a -> c
productOf l = getProduct . foldMapOf l Product
{-# INLINE productOf #-}

-- |
-- > sum = sumOf folded
--
-- > sumOf _1 :: (a, b) -> a
-- > sumOf (folded._1) :: (Foldable f, Num a) => f (a, b) -> a
--
-- > sumOf ::          Getter a b c d    -> a -> c
-- > sumOf ::          Lens a b c d      -> a -> c
-- > sumOf :: Num c => Fold a b c d      -> a -> c
-- > sumOf :: Num c => Traversal a b c d -> a -> c
sumOf :: Getting (Sum c) a b c d -> a -> c
sumOf l = getSum . foldMapOf l Sum
{-# INLINE sumOf #-}

-- |
--
-- When passed a 'Getter', 'traverseOf_' can work over a 'Functor'.
--
-- When passed a 'Fold', 'traverseOf_' requires an 'Applicative'.
--
-- > traverse_ = traverseOf_ folded
--
-- > traverseOf_ _2 :: Functor f => (c -> f e) -> (c1, c) -> f ()
-- > traverseOf_ traverseLeft :: Applicative f => (a -> f b) -> Either a c -> f ()
--
-- The rather specific signature of traverseOf_ allows it to be used as if the signature was either:
--
-- > traverseOf_ :: Functor f     => Getter a b c d    -> (c -> f e) -> a -> f ()
-- > traverseOf_ :: Functor f     => Lens a b c d      -> (c -> f e) -> a -> f ()
-- > traverseOf_ :: Applicative f => Fold a b c d      -> (c -> f e) -> a -> f ()
-- > traverseOf_ :: Applicative f => Traversal a b c d -> (c -> f e) -> a -> f ()
traverseOf_ :: Functor f => Getting (Traversed f) a b c d -> (c -> f e) -> a -> f ()
traverseOf_ l f = getTraversed . foldMapOf l (Traversed . void . f)
{-# INLINE traverseOf_ #-}

-- |
-- > for_ = forOf_ folded
--
-- > forOf_ :: Functor f     => Getter a b c d    -> a -> (c -> f e) -> f ()
-- > forOf_ :: Functor f     => Lens a b c d      -> a -> (c -> f e) -> f ()
-- > forOf_ :: Applicative f => Fold a b c d      -> a -> (c -> f e) -> f ()
-- > forOf_ :: Applicative f => Traversal a b c d -> a -> (c -> f e) -> f ()
forOf_ :: Functor f => Getting (Traversed f) a b c d -> a -> (c -> f e) -> f ()
forOf_ l a f = traverseOf_ l f a
{-# INLINE forOf_ #-}

-- |
-- > sequenceA_ = sequenceAOf_ folded
--
-- > sequenceAOf_ :: Functor f     => Getter a b (f ()) d    -> a -> f ()
-- > sequenceAOf_ :: Functor f     => Lens a b (f ()) d      -> a -> f ()
-- > sequenceAOf_ :: Applicative f => Fold a b (f ()) d      -> a -> f ()
-- > sequenceAOf_ :: Applicative f => Traversal a b (f ()) d -> a -> f ()
sequenceAOf_ :: Functor f => Getting (Traversed f) a b (f ()) d -> a -> f ()
sequenceAOf_ l = getTraversed . foldMapOf l (Traversed . void)
{-# INLINE sequenceAOf_ #-}

-- |
-- > mapM_ = mapMOf_ folded
--
-- > mapMOf_ :: Monad m => Getter a b c d    -> (c -> m e) -> a -> m ()
-- > mapMOf_ :: Monad m => Lens a b c d      -> (c -> m e) -> a -> m ()
-- > mapMOf_ :: Monad m => Fold a b c d      -> (c -> m e) -> a -> m ()
-- > mapMOf_ :: Monad m => Traversal a b c d -> (c -> m e) -> a -> m ()
mapMOf_ :: Monad m => Getting (Action m) a b c d -> (c -> m e) -> a -> m ()
mapMOf_ l f = getAction . foldMapOf l (Action . liftM skip . f)
{-# INLINE mapMOf_ #-}

-- |
-- > forM_ = forMOf_ folded
--
-- > forMOf_ :: Monad m => Getter a b c d    -> a -> (c -> m e) -> m ()
-- > forMOf_ :: Monad m => Lens a b c d      -> a -> (c -> m e) -> m ()
-- > forMOf_ :: Monad m => Fold a b c d      -> a -> (c -> m e) -> m ()
-- > forMOf_ :: Monad m => Traversal a b c d -> a -> (c -> m e) -> m ()
forMOf_ :: Monad m => Getting (Action m) a b c d -> a -> (c -> m e) -> m ()
forMOf_ l a f = mapMOf_ l f a
{-# INLINE forMOf_ #-}

-- |
-- > sequence_ = sequenceOf_ folded
--
-- > sequenceOf_ :: Monad m => Getter a b (m b) d    -> a -> m ()
-- > sequenceOf_ :: Monad m => Lens a b (m b) d      -> a -> m ()
-- > sequenceOf_ :: Monad m => Fold a b (m b) d      -> a -> m ()
-- > sequenceOf_ :: Monad m => Traversal a b (m b) d -> a -> m ()
sequenceOf_ :: Monad m => Getting (Action m) a b (m c) d -> a -> m ()
sequenceOf_ l = getAction . foldMapOf l (Action . liftM skip)
{-# INLINE sequenceOf_ #-}

-- | The sum of a collection of actions, generalizing 'concatOf'.
--
-- > asum = asumOf folded
--
-- > asumOf :: Alternative f => Getter a b c d    -> a -> f c
-- > asumOf :: Alternative f => Lens a b c d      -> a -> f c
-- > asumOf :: Alternative f => Fold a b c d      -> a -> f c
-- > asumOf :: Alternative f => Traversal a b c d -> a -> f c
asumOf :: Alternative f => Getting (Endo (f c)) a b (f c) d -> a -> f c
asumOf l = foldrOf l (<|>) Applicative.empty
{-# INLINE asumOf #-}

-- | The sum of a collection of actions, generalizing 'concatOf'.
--
-- > msum = msumOf folded
--
-- > msumOf :: MonadPlus m => Getter a b c d    -> a -> m c
-- > msumOf :: MonadPlus m => Lens a b c d      -> a -> m c
-- > msumOf :: MonadPlus m => Fold a b c d      -> a -> m c
-- > msumOf :: MonadPlus m => Traversal a b c d -> a -> m c
msumOf :: MonadPlus m => Getting (Endo (m c)) a b (m c) d -> a -> m c
msumOf l = foldrOf l mplus mzero
{-# INLINE msumOf #-}

-- |
-- > elem = elemOf folded
--
-- > elemOf :: Eq c => Getter a b c d    -> c -> a -> Bool
-- > elemOf :: Eq c => Lens a b c d      -> c -> a -> Bool
-- > elemOf :: Eq c => Fold a b c d      -> c -> a -> Bool
-- > elemOf :: Eq c => Traversal a b c d -> c -> a -> Bool
elemOf :: Eq c => Getting Any a b c d -> c -> a -> Bool
elemOf l = anyOf l . (==)
{-# INLINE elemOf #-}

-- |
-- > notElem = notElemOf folded
--
-- > notElemOf :: Eq c => Getter a b c d    -> c -> a -> Bool
-- > notElemOf :: Eq c => Fold a b c d      -> c -> a -> Bool
-- > notElemOf :: Eq c => Lens a b c d      -> c -> a -> Bool
-- > notElemOf :: Eq c => Traversal a b c d -> c -> a -> Bool
notElemOf :: Eq c => Getting All a b c d -> c -> a -> Bool
notElemOf l = allOf l . (/=)
{-# INLINE notElemOf #-}

-- |
-- > concatMap = concatMapOf folded
--
-- > concatMapOf :: Getter a b c d    -> (c -> [e]) -> a -> [e]
-- > concatMapOf :: Lens a b c d      -> (c -> [e]) -> a -> [e]
-- > concatMapOf :: Fold a b c d      -> (c -> [e]) -> a -> [e]
-- > concatMapOf :: Traversal a b c d -> (c -> [e]) -> a -> [e]
concatMapOf :: Getting [e] a b c d -> (c -> [e]) -> a -> [e]
concatMapOf l ces a = getConst  (l (Const . ces) a)
{-# INLINE concatMapOf #-}

-- |
-- > concat = concatOf folded
--
-- > concatOf :: Getter a b [e] d -> a -> [e]
-- > concatOf :: Lens a b [e] d -> a -> [e]
-- > concatOf :: Fold a b [e] d -> a -> [e]
-- > concatOf :: a b [e] d -> a -> [e]
concatOf :: Getting [e] a b [e] d -> a -> [e]
concatOf = view
{-# INLINE concatOf #-}

-- |
-- Note: this can be rather inefficient for large containers.
--
-- > length = lengthOf folded
--
-- > lengthOf _1 :: (a, b) -> Int
-- > lengthOf _1 = 1
-- > lengthOf (folded.folded) :: Foldable f => f (g a) -> Int
--
-- > lengthOf :: Getter a b c d    -> a -> Int
-- > lengthOf :: Lens a b c d      -> a -> Int
-- > lengthOf :: Fold a b c d      -> a -> Int
-- > lengthOf :: Traversal a b c d -> a -> Int
lengthOf :: Getting (Sum Int) a b c d -> a -> Int
lengthOf l = getSum . foldMapOf l (\_ -> Sum 1)
{-# INLINE lengthOf #-}

-- | Perform a safe 'head' of a 'Fold' or 'Traversal' or retrieve 'Just' the result
-- from a 'Getter' or 'Lens'.
--
-- > listToMaybe . toList = headOf folded
--
-- > headOf :: Getter a b c d    -> a -> Maybe c
-- > headOf :: Lens a b c d      -> a -> Maybe c
-- > headOf :: Fold a b c d      -> a -> Maybe c
-- > headOf :: Traversal a b c d -> a -> Maybe c
headOf :: Getting (First c) a b c d -> a -> Maybe c
headOf l = getFirst . foldMapOf l (First . Just)
{-# INLINE headOf #-}

-- | Perform a safe 'last' of a 'Fold' or 'Traversal' or retrieve 'Just' the result
-- from a 'Getter' or 'Lens'.
--
-- > lastOf :: Getter a b c d    -> a -> Maybe c
-- > lastOf :: Lens a b c d      -> a -> Maybe c
-- > lastOf :: Fold a b c d      -> a -> Maybe c
-- > lastOf :: Traversal a b c d -> a -> Maybe c
lastOf :: Getting (Last c) a b c d -> a -> Maybe c
lastOf l = getLast . foldMapOf l (Last . Just)
{-# INLINE lastOf #-}

-- |
-- Returns 'True' if this 'Fold' or 'Traversal' has no targets in the given container.
--
-- Note: nullOf on a valid 'Lens' or 'Getter' should always return 'False'
--
-- > null = nullOf folded
--
-- This may be rather inefficient compared to the 'null' check of many containers.
--
-- > nullOf _1 :: (a, b) -> Int
-- > nullOf _1 = False
-- > nullOf (folded._1.folded) :: Foldable f => f (g a, b) -> Bool
--
-- > nullOf :: Getter a b c d    -> a -> Bool
-- > nullOf :: Lens a b c d      -> a -> Bool
-- > nullOf :: Fold a b c d      -> a -> Bool
-- > nullOf :: Traversal a b c d -> a -> Bool
nullOf :: Getting All a b c d -> a -> Bool
nullOf l = getAll . foldMapOf l (\_ -> All False)
{-# INLINE nullOf #-}

-- |
-- Obtain the maximum element (if any) targeted by a 'Fold' or 'Traversal'
--
-- Note: maximumOf on a valid 'Lens' or 'Getter' will always return 'Just' a value.
--
-- > maximum = fromMaybe (error "empty") . maximumOf folded
--
-- > maximumOf ::          Getter a b c d    -> a -> Maybe c
-- > maximumOf ::          Lens a b c d      -> a -> Maybe c
-- > maximumOf :: Ord c => Fold a b c d      -> a -> Maybe c
-- > maximumOf :: Ord c => Traversal a b c d -> a -> Maybe c
maximumOf :: Getting (Max c) a b c d -> a -> Maybe c
maximumOf l = getMax . foldMapOf l Max
{-# INLINE maximumOf #-}

-- |
-- Obtain the minimum element (if any) targeted by a 'Fold' or 'Traversal'
--
-- Note: minimumOf on a valid 'Lens' or 'Getter' will always return 'Just' a value.
--
-- > minimum = fromMaybe (error "empty") . minimumOf folded
--
-- > minimumOf ::          Getter a b c d    -> a -> Maybe c
-- > minimumOf ::          Lens a b c d      -> a -> Maybe c
-- > minimumOf :: Ord c => Fold a b c d      -> a -> Maybe c
-- > minimumOf :: Ord c => Traversal a b c d -> a -> Maybe c
minimumOf :: Getting (Min c) a b c d -> a -> Maybe c
minimumOf l = getMin . foldMapOf l Min
{-# INLINE minimumOf #-}

-- |
-- Obtain the maximum element (if any) targeted by a 'Fold', 'Traversal', 'Lens'
-- or 'Getter' according to a user supplied ordering.
--
-- > maximumBy cmp = fromMaybe (error "empty") . maximumByOf folded cmp
--
-- > maximumByOf :: Getter a b c d    -> (c -> c -> Ordering) -> a -> Maybe c
-- > maximumByOf :: Lens a b c d      -> (c -> c -> Ordering) -> a -> Maybe c
-- > maximumByOf :: Fold a b c d      -> (c -> c -> Ordering) -> a -> Maybe c
-- > maximumByOf :: Traversal a b c d -> (c -> c -> Ordering) -> a -> Maybe c
maximumByOf :: Getting (Endo (Maybe c)) a b c d -> (c -> c -> Ordering) -> a -> Maybe c
maximumByOf l cmp = foldrOf l step Nothing where
  step a Nothing  = Just a
  step a (Just b) = Just (if cmp a b == GT then a else b)
{-# INLINE maximumByOf #-}

-- |
-- Obtain the minimum element (if any) targeted by a 'Fold', 'Traversal', 'Lens'
-- or 'Getter' according to a user supplied ordering.
--
-- > minimumBy cmp = fromMaybe (error "empty") . minimumByOf folded cmp
--
-- > minimumByOf :: Getter a b c d    -> (c -> c -> Ordering) -> a -> Maybe c
-- > minimumByOf :: Lens a b c d      -> (c -> c -> Ordering) -> a -> Maybe c
-- > minimumByOf :: Fold a b c d      -> (c -> c -> Ordering) -> a -> Maybe c
-- > minimumByOf :: Traversal a b c d -> (c -> c -> Ordering) -> a -> Maybe c
minimumByOf :: Getting (Endo (Maybe c)) a b c d -> (c -> c -> Ordering) -> a -> Maybe c
minimumByOf l cmp = foldrOf l step Nothing where
  step a Nothing  = Just a
  step a (Just b) = Just (if cmp a b == GT then b else a)
{-# INLINE minimumByOf #-}

-- | The 'findOf' function takes a lens, a predicate and a structure and returns
-- the leftmost element of the structure matching the predicate, or
-- 'Nothing' if there is no such element.
findOf :: Getting (First c) a b c d -> (c -> Bool) -> a -> Maybe c
findOf l p = getFirst . foldMapOf l step where
  step c
    | p c       = First (Just c)
    | otherwise = First Nothing
{-# INLINE findOf #-}

-- |
-- A variant of 'foldrOf' that has no base case and thus may only be applied
-- to lenses and structures such that the lens views at least one element of
-- the structure.
--
-- > foldr1Of l f = Prelude.foldr1 f . toListOf l
--
-- > foldr1 = foldr1Of folded
--
-- > foldr1Of :: Getter a b c d    -> (c -> c -> c) -> a -> c
-- > foldr1Of :: Lens a b c d      -> (c -> c -> c) -> a -> c
-- > foldr1Of :: Fold a b c d      -> (c -> c -> c) -> a -> c
-- > foldr1Of :: Traversal a b c d -> (c -> c -> c) -> a -> c
foldr1Of :: Getting (Endo (Maybe c)) a b c d -> (c -> c -> c) -> a -> c
foldr1Of l f xs = fromMaybe (error "foldr1Of: empty structure")
                            (foldrOf l mf Nothing xs) where
  mf x Nothing = Just x
  mf x (Just y) = Just (f x y)
{-# INLINE foldr1Of #-}

-- | A variant of 'foldlOf' that has no base case and thus may only be applied to lenses and strutures such
-- that the lens views at least one element of the structure.
--
-- > foldl1Of l f = Prelude.foldl1Of l f . toList
--
-- > foldl1 = foldl1Of folded
--
-- > foldl1Of :: Getter a b c d    -> (c -> c -> c) -> a -> c
-- > foldl1Of :: Lens a b c d      -> (c -> c -> c) -> a -> c
-- > foldl1Of :: Fold a b c d      -> (c -> c -> c) -> a -> c
-- > foldl1Of :: Traversal a b c d -> (c -> c -> c) -> a -> c
foldl1Of :: Getting (Dual (Endo (Maybe c))) a b c d -> (c -> c -> c) -> a -> c
foldl1Of l f xs = fromMaybe (error "foldl1Of: empty structure") (foldlOf l mf Nothing xs) where
  mf Nothing y = Just y
  mf (Just x) y = Just (f x y)
{-# INLINE foldl1Of #-}

-- | Strictly fold right over the elements of a structure.
--
-- > foldr' = foldrOf' folded
--
-- > foldrOf' :: Getter a b c d    -> (c -> e -> e) -> e -> a -> e
-- > foldrOf' :: Lens a b c d      -> (c -> e -> e) -> e -> a -> e
-- > foldrOf' :: Fold a b c d      -> (c -> e -> e) -> e -> a -> e
-- > foldrOf' :: Traversal a b c d -> (c -> e -> e) -> e -> a -> e
foldrOf' :: Getting (Dual (Endo (e -> e))) a b c d -> (c -> e -> e) -> e -> a -> e
foldrOf' l f z0 xs = foldlOf l f' id xs z0
  where f' k x z = k $! f x z
{-# INLINE foldrOf' #-}

-- | Fold over the elements of a structure, associating to the left, but strictly.
--
-- > foldl' = foldlOf' folded
--
-- > foldlOf' :: Getter a b c d    -> (e -> c -> e) -> e -> a -> e
-- > foldlOf' :: Lens a b c d      -> (e -> c -> e) -> e -> a -> e
-- > foldlOf' :: Fold a b c d      -> (e -> c -> e) -> e -> a -> e
-- > foldlOf' :: Traversal a b c d -> (e -> c -> e) -> e -> a -> e
foldlOf' :: Getting (Endo (e -> e)) a b c d -> (e -> c -> e) -> e -> a -> e
foldlOf' l f z0 xs = foldrOf l f' id xs z0
  where f' x k z = k $! f z x
{-# INLINE foldlOf' #-}

-- | Monadic fold over the elements of a structure, associating to the right,
-- i.e. from right to left.
--
-- > foldrM = foldrMOf folded
--
-- > foldrMOf :: Monad m => Getter a b c d    -> (c -> e -> m e) -> e -> a -> m e
-- > foldrMOf :: Monad m => Lens a b c d      -> (c -> e -> m e) -> e -> a -> m e
-- > foldrMOf :: Monad m => Fold a b c d      -> (c -> e -> m e) -> e -> a -> m e
-- > foldrMOf :: Monad m => Traversal a b c d -> (c -> e -> m e) -> e -> a -> m e
foldrMOf :: Monad m
         => Getting (Dual (Endo (e -> m e))) a b c d
         -> (c -> e -> m e) -> e -> a -> m e
foldrMOf l f z0 xs = foldlOf l f' return xs z0
  where f' k x z = f x z >>= k
{-# INLINE foldrMOf #-}

-- | Monadic fold over the elements of a structure, associating to the left,
-- i.e. from left to right.
--
-- > foldlM = foldlMOf folded
--
-- > foldlMOf :: Monad m => Getter a b c d    -> (e -> c -> m e) -> e -> a -> m e
-- > foldlMOf :: Monad m => Lens a b c d      -> (e -> c -> m e) -> e -> a -> m e
-- > foldlMOf :: Monad m => Fold a b c d      -> (e -> c -> m e) -> e -> a -> m e
-- > foldlMOf :: Monad m => Traversal a b c d -> (e -> c -> m e) -> e -> a -> m e
foldlMOf :: Monad m
         => Getting (Endo (e -> m e)) a b c d
         -> (e -> c -> m e) -> e -> a -> m e
foldlMOf l f z0 xs = foldrOf l f' return xs z0
  where f' x k z = f z x >>= k
{-# INLINE foldlMOf #-}

------------------------------------------------------------------------------
-- Traversals
------------------------------------------------------------------------------

-- | This is the traversal that never succeeds at returning any values
--
-- > traverseNothing :: Applicative f => (c -> f d) -> a -> f a
traverseNothing :: Traversal a a c d
traverseNothing = const pure
{-# INLINE traverseNothing #-}

-- | A traversal for tweaking the left-hand value in an Either:
--
-- > traverseLeft :: Applicative f
-- >              => (a -> f b) -> Either a c -> f (Either b c)
traverseLeft :: Traversal (Either a c) (Either b c) a b
traverseLeft f (Left a)  = Left <$> f a
traverseLeft _ (Right c) = pure $ Right c
{-# INLINE traverseLeft #-}

-- | traverse the right-hand value in an Either:
--
-- > traverseRight :: Applicative f
-- >               => (a -> f b) -> Either c a -> f (Either c a)
-- > traverseRight = traverse
--
-- Unfortunately the instance for 'Traversable (Either c)' is still missing
-- from base, so this can't just be 'traverse'
traverseRight :: Traversal (Either c a) (Either c b) a b
traverseRight _ (Left c) = pure $ Left c
traverseRight f (Right a) = Right <$> f a
{-# INLINE traverseRight #-}

-- | This provides a 'Traversal' that checks a predicate on a key before
-- allowing you to traverse into a value.
traverseValue :: (k -> Bool) -> Simple Traversal (k, v) v
traverseValue p f kv@(k,v)
  | p k       = (,) k <$> f v
  | otherwise = pure kv
{-# INLINE traverseValue #-}

------------------------------------------------------------------------------
-- Cloning Lenses
------------------------------------------------------------------------------

-- | Cloning a 'Lens' is one way to make sure you arent given
-- something weaker, such as a 'Traversal' and can be used
-- as a way to pass around lenses that have to be monomorphic in 'f'.
--
-- Note: This only accepts a proper 'Lens', because 'IndexedStore' lacks its
-- (admissable) Applicative instance.
clone :: Functor f
      => LensLike (IndexedStore c d) a b c d
      -> (c -> f d) -> a -> f b
clone f cfd a = case f (IndexedStore id) a of
  IndexedStore db c -> db <$> cfd c
{-# INLINE clone #-}

------------------------------------------------------------------------------
-- Transforming Traversals
------------------------------------------------------------------------------

-- | This allows you to 'traverse' the elements of a 'Traversal' in the
-- opposite order.
--
-- Note: 'reversed' is similar, but is able to accept a 'Fold' (or 'Getter')
-- and produce a 'Fold' (or 'Getter').
--
-- This requires at least a 'Traversal' (or 'Lens') and can produce a
-- 'Traversal' (or 'Lens') in turn.
backwards :: LensLike (Backwards f) a b c d -> LensLike f a b c d
backwards l f = getBackwards . l (Backwards . f)
{-# INLINE backwards #-}
