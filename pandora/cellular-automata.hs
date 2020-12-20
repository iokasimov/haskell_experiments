import "pandora" Pandora.Core
import "pandora" Pandora.Paradigm
import "pandora" Pandora.Pattern

import GHC.Int (Int, eqInt)
import Prelude (IO, Char, Show (show), putStr, print, reverse, (-), (<>), map)
import Control.Concurrent (threadDelay)

import qualified Prelude as Prelude (traverse)

type Status = Boolean

type Field = Zipper Stream Status

type Neighbours = Status :*: Status :*: Status

start :: Field
start = let desert = repeat False
	in Tap True . TU $ desert :^: desert

rule90 :: Neighbours -> Status
rule90 (True :*: True :*: True) = False
rule90 (True :*: True :*: False) = True
rule90 (True :*: False :*: True) = False
rule90 (True :*: False :*: False) = True
rule90 (False :*: True :*: True) = True
rule90 (False :*: True :*: False) = False
rule90 (False :*: False :*: True) = True
rule90 (False :*: False :*: False) = False

neighbourhood :: Field -> Neighbours
neighbourhood z = extract (sub @Left ^. z) :*: extract z :*: extract (sub @Right ^. z)

display :: Natural -> Zipper Stream a -> [a]
display n (Tap x (TU (bs :^: fs))) = take_n n [] bs <> [x] <> reverse (take_n n [] fs)

take_n :: Natural -> [a] -> Stream a -> [a]
take_n (Natural n) r (Construct x (Identity next)) = take_n n (x : r) next
take_n Zero r _ = r

instance Setoid Int where
	x == y = if eqInt x y then True else False

natural :: Int -> Natural
natural n = n == 0 ? Zero $ Natural . natural $ n - 1

instance Monotonic (Construction Identity a) a where
	reduce f r ~(Construct x (Identity xs)) = f x $ reduce f r xs

lifecycle_1d act being = do
	threadDelay 1000000
	print $ display (natural 25) being
	lifecycle_1d act $ being =>> act

--------------------------------------------------------------------------------

-- type II = Zipper Stream <:.> Zipper Stream
type II = Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)

instance Covariant II where
	f <$> TU zz = TU $ f <$$> zz

instance Extractable II where
	extract = extract . extract . run

instance Extendable II where
	zz =>> f = f <$> TU (horizontal <$> vertical zz) where

		horizontal, vertical :: II a -> Zipper Stream (II a)
		horizontal z = Tap z . TU $ move (TU . (rotate @Left <$>) . run) z :^: move (TU . (rotate @Right <$>) . run) z
		vertical z = Tap z . TU $ move (TU . rotate @Left . run) z :^: move (TU . rotate @Right . run) z

		move :: (Extractable t, Pointable t) => (a -> a) -> a -> Construction t a
		move f x = extract . deconstruct $ point . f .-+ x

instance Substructure Down (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) where
	type Substructural Down (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) a = Stream :. Zipper Stream := a
	substructure (run . extract -> Tap focused (TU (down :^: up))) = Store $ down :*: Tag . TU . Tap focused . TU . (:^: up)

instance Substructure Up (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) where
	type Substructural Up (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) a = Stream :. Zipper Stream := a
	substructure (run . extract -> Tap focused (TU (down :^: up))) = Store $ up :*: Tag . TU . Tap focused . TU . (down :^:)

instance Substructure Left (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) where
	type Substructural Left (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) a = Zipper Stream :. Stream := a
	substructure (run . extract -> Tap x (TU (d :^: u))) =
		let target = Tap (sub @Left ^. x) . TU $ view (sub @Left) <$> d :^: view (sub @Left) <$> u in
		let around lx = (set (sub @Left) <$> sub @Left ^. lx <*> d) :^: (set (sub @Left) <$> sub @Left ^. lx <*> u) in
		Store $ target :*: \lx -> Tag . TU . Tap (sub @Left .~ extract lx $ x) . TU $ around lx

instance Substructure Right (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) where
	type Substructural Right (Tap (Delta <:.> Stream) <:.> Tap (Delta <:.> Stream)) a = Zipper Stream :. Stream := a
	substructure (run . extract -> Tap x (TU (d :^: u))) =
		let target = Tap (sub @Right ^. x) . TU $ view (sub @Right) <$> d :^: view (sub @Right) <$> u in
		let around rx = (set (sub @Right) <$> sub @Right ^. rx <*> d) :^: (set (sub @Right) <$> sub @Right ^. rx <*> u) in
		Store $ target :*: \rx -> Tag . TU . Tap (sub @Right .~ extract rx $ x) . TU $ around rx

type Around = Status -- current
	:*: Status :*: Status -- horizontal
	:*: Status :*: Status -- vertical
	:*: Status :*: Status -- major diagonal
	:*: Status :*: Status -- minor diagonal

around :: II Status -> Around
around z = extract z :*: plane (sub @Left) :*: plane (sub @Right) :*: plane (sub @Up) :*: plane (sub @Down)
	:*: slant (sub @Down) (sub @Left) :*: slant (sub @Up) (sub @Right)
	:*: slant (sub @Up) (sub @Left) :*: slant (sub @Down) (sub @Right) where

	plane :: (Extractable t, Extractable u)
		=> II Status :-. t :. u := Status -> Status
	plane lens = extract . extract $ lens ^. z

	slant :: II Status :-. Stream :. Zipper Stream := Status
		-> Zipper Stream Status :-. Stream Status -> Status
	slant vl hl = extract . view hl . extract . view vl $ z

initial :: II Status
initial = TU . Tap one . TU $ only :^: only where

	only :: Stream :. Zipper Stream := Status
	only = Construct one . Identity $ repeat noone

	one :: Zipper Stream Status
	one = Tap True . TU $ (Construct True . Identity $ repeat False) :^: (Construct True . Identity $ repeat False)

	noone :: Zipper Stream Status
	noone = Tap False . TU $ repeat False :^: repeat False

liferule :: Around -> Status
liferule (focused :*: neighbors) = case reduce (\status acc -> status ? acc + one $ acc) zero neighbors of
	Natural (Natural Zero) -> focused
	Natural (Natural (Natural Zero)) -> True
	_ -> False

display_2d :: Natural -> II Status -> [[Status]]
display_2d n (TU (Tap x (TU (bs :^: fs)))) = (take_n n [] $ display n <$> bs)
	<> [display n x] <> reverse (take_n n [] $ display n <$> fs)

lifecycle_2d :: (II Status -> Status) -> II Status -> IO ()
lifecycle_2d act being = do
	threadDelay 1000000
	putStr "\ESC[2J"
	Prelude.traverse print $ display_2d (natural 15) being
	lifecycle_2d act $ being =>> act

--------------------------------------------------------------------------------

deriving instance (Show a, Show b) => Show (a :*: b)

instance Show Boolean where
	show True = "*"
	show False = " "

instance Show Natural where
	show Zero = "0"
	show (Natural n) = "1" <> show n

main = lifecycle_2d (liferule . around) initial