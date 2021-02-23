

tPosition struc 
	x dd ?
	y dd ?
	z dd ?
tPosition ends
 
tPos struc 
	x dw ?
	y dw ?
tPos ends 


tColor struc
	R dd ?
	G dd ?
	B dd ?
tColor ends
tCol struc
	R dw ?
	G dw ?
	B dw ?
tCol ends

tPixel struct
	Pos tPos <>
	Col tCol <>
tPixel ends

tSphere struct 
	Position tPosition <>
	Radius   dd        ?
	Color    tColor    <>
tSphere ends

tColorMix struct
	SkyColor    tColor <>
	LightColor  tColor <>
	FogColor    tColor <>
	GetSkyColor tColor <>
tColorMix ends


tBB struct
	O  tPosition <>
	N  tPosition <>
tBB ends

tConst struct
	F65536    dd ?;65536.0
	F30625    dd ?;3.0625
	FM175     dd ?;-1.75
	FTimeFreq dd ?;1193186.0
	FBigValue dd ?;9999999.0
	FZero     dd ?;0
	F05       dd ?;0.5
	C2        dw ?;2
	C255      dw ?;255
	C256      dw ?;256
	C1000     dw ?;1000
tConst ends

tData struct
	DistEpsilon    dd ?;0.01
	DistEpsilon2   dd ?;0.02
	FogDistance    dd ?;100.0
	SavedVideoMode dw ?;0
	TempW          dw ?;0
	SizeOf_Sphere  dw ?;sizeof tSphere
	Res            tPos <>;<320,200>
tData ends


tLightRay struc
	O    tPosition    <>
	struc dir
		Ray   tPosition <>
		Light tPosition <>
	ends
	D    dd ?
tLightRay ends

tMapCast struc
	O tPosition <>
    N tPosition <>
    D dd ?
    I dw ?
tMapCast ends

tMapDist struc
	O tPosition <>
	D dd ?
	I dw ?
tMapDist ends



tMapCastDist struct
	Ray     tLightRay <>
	MapCast tMapCast  <>
	MapDist tMapDist  <>
tMapCastDist ends



tREG struct
	ax_ dw ?
	cx_ dw ?
	dx_ dw ?
	bx_ dw ?
	sp_ dw ?
	bp_ dw ?
	si_ dw ?
	di_ dw ?
tREG ends


tClass struct
	Val_  tConst        <>
	Data_ tData         <>
	DM    db  16*16  dup(?)
	M	  tMapCastDist  <>
	Mask_ tColor        <>
	Mix   tColorMix     <>
    Cam   tPosition     <>
    BB    tBB           <>
	P     tPixel        <>
	S     tSphere NumSpheres dup(<>)
	
	R     tREG          <>
	Check dw            <> ;0AA55h
tClass ends
STRUCTCHECK TEXTEQU <@CatStr(%($ - offset _this))>


