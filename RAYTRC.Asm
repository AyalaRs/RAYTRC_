;******************************************************************************
; DOS Ray-tracing rendering Demo
; by 0xAA55
; 2021-2-17
;
; This program is a DOS `COM` program which is able to be run in native DOS
; system in Real mode x86 CPU
;******************************************************************************



.model tiny
.286
;option prologue:none
;option epilogue:none
option casemap:none
option prologue:prologuedef
option epilogue:epiloguedef

;assume si:error
;assume di:error

;DEBUGMODE EQU 1

Interlaced equ 1

NumSpheres equ 3
WWWWW      equ 320
HHHHH      equ 200

include RAYTRC.inc


;std
;.data
;#

;shellcode
.code
_entry: 
	call Start
;#	
	
	
_this   label tClass

;tConst struct
	gF65536    dd 65536.0
	gF30625    dd 3.0625
	gFM175     dd -1.75
	gFTimeFreq dd 1193186.0
	gFBigValue dd 9999999.0
	gFZero     dd 0
	gF05       dd 0.5
	gC2        dw 2
	gC255      dw 255
	gC256      dw 256
	gC1000     dw 1000
;tConst ends
	
	
;tData struct
	gDistEpsilon    dd 0.01
	gDistEpsilon2   dd 0.02
	gFogDistance    dd 100.0
	gSavedVideoMode dw 0
	gTempW          dw 0
	gSizeOf_Sphere  dw sizeof tSphere
	gRes            tPos <WWWWW,HHHHH>
;tData ends


DitherMatrix label byte
	dm_y = 0
	REPEAT 16
		dm_x  = 0
		REPEAT 16
				xor_val = dm_x XOR dm_y
				dm_val =           (((xor_val AND 01h) SHR 0) SHL 7) OR (((dm_y AND 01) SHR 0) SHL 6)
				dm_val = dm_val OR (((xor_val AND 02h) SHR 1) SHL 5) OR (((dm_y AND 02) SHR 1) SHL 4)
				dm_val = dm_val OR (((xor_val AND 04h) SHR 2) SHL 3) OR (((dm_y AND 04) SHR 2) SHL 2)
				dm_val = dm_val OR (((xor_val AND 08h) SHR 3) SHR 1) OR (((dm_y AND 08) SHR 3) SHR 0)
				db dm_val
				dm_x = dm_x + 1
		ENDM
		dm_y = dm_y + 1
	ENDM


	SampleDepth     EQU 12
	MapCast_Iterate EQU 12

;tMapCastDist struct	
	gLightRay	tLightRay  <<0,0,0>,<<0,0,0>,<1.0,-1.0, 1.0>>,0>
	gMapCast    tMapCast  <<0,0,0>,<0,0,0>,0,0>
	gMapDist    tMapDist  <<0,0,0>,0,0>
;tMapCastDist ends

	gMask       tColor    <0, 0, 0>

	gColorMix    tColorMix <<0.2, 0.5, 0.8>,\
                      <1.0, 0.8, 0.6>,\
                      <0.8, 0.9, 1.0>,\
                      <0, 0, 0>\
                      >
	gCamPos     tPosition < 0.0, 2.0, 7.0>

;tBB struct
	gBB         tPosition < 2.5, 4.5, 3.5>
	gBBneg      tPosition <-4.5,-0.5,-0.5>
;tBB ends

	gPixel      tPixel    <<0, 0>,<0, 0, 0>>

	gSpheres    tSphere << 0.0, 2.0, 0.0>, 2.0, <0.7, 0.9, 0.1>>, \
    	                 << 1.0, 1.0, 2.0>, 1.0, <0.1, 0.7, 0.9>>,  \
        	             <<-3.0, 1.0, 0.0>, 1.0, <0.9, 0.1, 0.7>>
                    
	gReg       dw 8 dup(0)
	gCheck     dw 0aa55h   ;data end for check
	
IF ($ - offset _this) NE (sizeof tClass) 
%   ECHO STRUCTCHECK
%   ECHO  @CatStr(%(sizeof tClass) )
	.ERR
ENDIF
               db '$',0
	
;std
;.code
;org 100h
;#
Start:
;shellcode
	pop bx ;shellcode
	
;std
    ;lea bx,offset _this
	assume bx:ptr tClass
	
	cmp [bx].Check, 0AA55h 
	mov al,'1'
	jnz @F
	
	call SetupVideoMode  
	
	cmp [bx].Check, 0AA55h 
	mov al,'2'
	jnz @F
	
	call RenderScreen
	
	cmp [bx].Check, 0AA55h 
	mov al,'3'
	jnz @F
	
	call RestoreVideoMode
	mov al,'4'

@@: call @F
	byte ' potato','$',13,10
@@:	pop bx
	mov [bx],al
	mov dx,bx
	mov ah,9
	int 21h	
	
	;Exit program
	int 20h
	ret
	
;******************************************************************************
; Setup our specific palette to use our color-system.
; We use RGB:233 color format to encode the color index, and it's easier to
; implement the ordered-dithering algorithm to gain a better appearance.
;******************************************************************************
SetupPalette proc
	
	;Set up palette
	mov bl, 0
	mov cx, 256
	
LoopSetPalette:

		push cx
		mov dx, 03C8h
		mov al, bl ;The current color index
		out dx, al

		inc dl ;0x03C9 port

		;Red: 2 bits
		and al, 03h
		mov bh, 55h
		mul bh
		out dx, al

		;Green: 3 bits
		mov al, bl
		mov cl, 2
		shr al, cl
		and al, 07h
		mov bh, 49h
		mul bh
		out dx, al

		;Blue: 3 bits
		mov al, bl
		mov cl, 5
		shr al, cl
		and al, 07h
		mul bh
		out dx, al

		;Increase the color index
		inc bl
		pop cx
	loop LoopSetPalette

	ret
SetupPalette endp


;******************************************************************************
; Setup video mode to 0x13: Graphic mode, 320x200 resolution, 256 colors.
; The VRAM buffer is 0xA000:0x0000
; Each byte of the buffer represents the color index of a palette.
; The previous video mode will be saved.
;******************************************************************************
SetupVideoMode proc
	;Get current display mode
	
	;push bx
	mov [bx].R.bp_,bp
	mov bp,bx
	
	mov ah, 0fh
	int 10h  ;The bx data is corrupted
	
	mov bx,bp
	mov byte ptr [bx].Data_.SavedVideoMode, al

	;Set display mode to 320x200 graphic 256-color mode
	mov ax, 13h
	int 10h   ;The bx data is corrupted
	
	mov bx,bp
	call SetupPalette ;The bx data is corrupted
	
	;pop bx
	mov bx,bp
	mov bp,[bx].R.bp_
	ret
SetupVideoMode endp

;******************************************************************************
; Restore the video mode to the saved video mode.
; The saved video mode was saved by calling `SetupVideoMode`.
;******************************************************************************

RestoreVideoMode proc
	mov [bx].R.bp_,bp
	mov bp,bx
	;Restore video mode
	mov ax, [bx].Data_.SavedVideoMode
	int 10h
	
	mov bx,bp
	mov bp,[bx].R.bp_
	ret
RestoreVideoMode endp
;******************************************************************************
; Pickup the best color for pixel position of `Pixel_X` and `Pixel_Y` with
; the color value of `Pixel_R` `Pixel_G` `Pixel_B`.
; Returns the best color index through register `AL`.
;******************************************************************************

PickColor proc uses si
	mov al, byte ptr [bx].P.Pos.x ;[gPixel.Pos.x]
	and al, 0fh
	mov ah, byte ptr [bx].P.Pos.y
	and ah, 0fh
	mov cl, 4
	shl ah, cl
	or al, ah
	mov ah, 0
		
	mov si,ax
	mov al,[si][bx].DM
;	push bx
;	lea bx,[bx].DM
;	xlatb
;	pop bx
	
	mov dl, al
	mov cl, 2
	shr dl, cl
	inc cl
	shr al, cl
	
	
;	lea bx,gPixel
;	assume bx:ptr tPixel
		
	add byte ptr [bx].P.Col.R, dl
	jnc @F
	mov byte ptr [bx].P.Col.R, 0FFh
@@:; .RedReady:
	add byte ptr [bx].P.Col.G, al
	jnc @F
	mov byte ptr [bx].P.Col.G, 0FFh
@@: ;.GreenReady:
	add byte ptr [bx].P.Col.B, al
	jnc @F
	mov byte ptr [bx].P.Col.B, 0FFh
@@: ;.BlueReady:

	and byte ptr [bx].P.Col.R, 0C0h
	and byte ptr [bx].P.Col.G, 0E0h
	and byte ptr [bx].P.Col.B, 0E0h
	mov al, byte ptr [bx].P.Col.R
	shr al, cl ;cl = 3
	or al, byte ptr [bx].P.Col.G
	shr al, cl
	or al, byte ptr [bx].P.Col.B
	

	ret
PickColor endp

;******************************************************************************
; Render the scene
;******************************************************************************
RenderScreen proc uses di si

	LOCAL Local_Cam_U:DWORD
	LOCAL Local_Cam_V:DWORD
	LOCAL Local_Cam_W:DWORD
	LOCAL Local_Cam_D:DWORD
	
	
	mov ax, 0a000h
	mov es, ax
	
	
	fld [bx].Val_.FM175;[FM175]
	fstp  [Local_Cam_W]

	;Do some initialize
	
;	lea bx,gLightRay.dir.Light
;	assume bx:ptr tPosition
	
	fld  [bx].M.Ray.dir.Light.x
	fmul st(0),st(0)
	fld  [bx].M.Ray.dir.Light.y
	fmul st(0),st(0)
	fadd
	fld  [bx].M.Ray.dir.Light.z
	fmul st(0),st(0)
	fadd
	fsqrt
	
	fld st(0)
	fdivr [bx].M.Ray.dir.Light.x
	fstp  [bx].M.Ray.dir.Light.x
	
	fld st(0)
	fdivr [bx].M.Ray.dir.Light.y
	fstp  [bx].M.Ray.dir.Light.y
	
	fdivr [bx].M.Ray.dir.Light.z
	fstp  [bx].M.Ray.dir.Light.z

	;di: Used to write display buffer
	xor di, di
	;Loop for scan lines
;	lea bx,gPixel
;	assume bx:ptr tPixel
	
	mov  [bx].P.Pos.y, 0
@@:
	.repeat
		;Calculate Ray-V
		mov ax, [bx].P.Pos.y
		add ax, ax
		sub ax, [bx].Data_.Res.y
		not ax
		inc ax
		
		mov word ptr [Local_Cam_V], ax
		fild word ptr [Local_Cam_V]
		fidiv [bx].Data_.Res.y
		fstp [Local_Cam_V]

		;Loop for pixels per scan line
		mov [bx].P.Pos.x,0
		
		.repeat
			;Calculate Ray-U
			mov ax, [bx].P.Pos.x
			add ax, ax
			sub ax, [bx].Data_.Res.x
			mov word ptr [Local_Cam_U], ax
			fild word ptr [Local_Cam_U]
			fidiv word ptr [bx].Data_.Res.y
			fst [Local_Cam_U]

			;Normalize Ray
			fmul st(0),st(0)
			fld [Local_Cam_V]
			fmul st(0),st(0)
			fadd
			fadd [bx].Val_.F30625;[F30625]
			fsqrt
			fst [Local_Cam_D]
			fdivr [Local_Cam_U]
			fstp  [bx].M.Ray.dir.Ray.x
			fld  [Local_Cam_V]
			fdiv  [Local_Cam_D]
			fstp  [bx].M.Ray.dir.Ray.y
			fld  [Local_Cam_W]
			fdiv  [Local_Cam_D]
			fstp  [bx].M.Ray.dir.Ray.z

			; Render the current pixel color
			call RenderScene
			
			;push si
			;mov si,[bx].P.Pos.x
			;and si,0ffh
			;mov al,[si][bx].DM
			;pop si
			
			stosb
			
	
			inc  [bx].P.Pos.x
		.until [bx].P.Pos.x >= WWWWW

		
IFDEF Interlaced

		lea di,[di+WWWWW]
		inc [bx].P.Pos.y
ENDIF
		inc [bx].P.Pos.y
	.until [bx].P.Pos.y>= HHHHH
	
IFDEF Interlaced
	and [bx].P.Pos.y,1
	mov [bx].P.Pos.y,1
	mov di,WWWWW
	jz	@B
ENDIF	
	
	
	; Wait for any keystroke to exit
	mov ah, 07h
	int 21h

	ret
RenderScreen endp


;******************************************************************************
; Pick up a color that represents the sky from the `RayDir` vector.
;******************************************************************************
GetSkyColor proc 
	; SunLum = Dot(RayDir, -LightDir)

	fld  [bx].M.Ray.dir.Ray.x
	fmul [bx].M.Ray.dir.Light.x
	fld  [bx].M.Ray.dir.Ray.y
	fmul [bx].M.Ray.dir.Light.y
	fadd
	fld  [bx].M.Ray.dir.Ray.z
	fmul [bx].M.Ray.dir.Light.z
	fadd
	fchs

	; SunLum = Max(SunLum, 0)
	fld st(0)
	fabs
	fadd
	fidiv [bx].Val_.C2 ;[C2]
	

	; SunLum = Pow(SunLum, LightPow)
	IF LightPow GT 0
		fld st(0)
		
		REPEAT LightPow - 1
		
		fmul st(0),st(1)
		ENDM
		fmul
	ENDIF

	; FogDensity = 1 - abs(RayDir_y)
	fld1
	fld  [bx].M.Ray.dir.Ray.y
	fabs
	fsub

	; Mix(SkyColor, FogColor, FogDensity)
;	lea bx,ColorMix
;	assume bx:ptr tColorMix
	
	fld st(0)
	fmul  [bx].Mix.FogColor.R
	fstp  [bx].Mix.GetSkyColor.R
	fld st(0)
	fmul  [bx].Mix.FogColor.G
	fstp  [bx].Mix.GetSkyColor.G
	fld st(0)
	fmul  [bx].Mix.FogColor.B
	fstp  [bx].Mix.GetSkyColor.B

	; 1 - FogDensity
	fld1
	fsubr
	fld st(0)
	fmul  [bx].Mix.SkyColor.R
	fadd  [bx].Mix.GetSkyColor.R
	fstp  [bx].Mix.GetSkyColor.R
	fld st(0)
	fmul  [bx].Mix.SkyColor.G
	fadd  [bx].Mix.GetSkyColor.G
	fstp  [bx].Mix.GetSkyColor.G

	fmul  [bx].Mix.SkyColor.B
	fadd  [bx].Mix.GetSkyColor.B
	fstp  [bx].Mix.GetSkyColor.B

	; LightColor
	fld st(0)
	fmul  [bx].Mix.LightColor.R
	fadd  [bx].Mix.GetSkyColor.R
	fstp  [bx].Mix.GetSkyColor.R
	fld st(0)
	fmul  [bx].Mix.LightColor.G
	fadd  [bx].Mix.GetSkyColor.G
	fstp  [bx].Mix.GetSkyColor.G

	fmul  [bx].Mix.LightColor.B
	fadd  [bx].Mix.GetSkyColor.B
	fstp  [bx].Mix.GetSkyColor.B

	ret
GetSkyColor endp
;******************************************************************************
; Pick up a color that represents the sky from the `RayDir` vector.
;******************************************************************************
MapDistProc proc uses si di
;	lea bx, gCastDistWithSpheres
;	assume bx:ptr tCastDistWithSpheres
	
	fld  [bx].M.MapDist.O.y
	fstp [bx].M.MapDist.D
	mov  [bx].M.MapDist.I,-1
	
	mov cx, NumSpheres
	mov si, 0
	mov di, 0

		
@@:

	fld  [si][bx].S.Position.x
	fsub [bx].M.MapDist.O.x
	fmul st(0),st(0)
	
	fld  [si][bx].S.Position.y
	fsub [bx].M.MapDist.O.y
	fmul st(0),st(0)
	fadd
	fld  [si][bx].S.Position.z
	fsub [bx].M.MapDist.O.z
	fmul st(0),st(0)
	fadd
	fsqrt
	fsub [si][bx].S.Radius
	fcom [bx].M.MapDist.D
	fstsw ax
	sahf
.if CARRY?
	fst  [bx].M.MapDist.D
	mov  [bx].M.MapDist.I, di
.endif
	fstp st(0)
	inc di
	add si,[bx].Data_.SizeOf_Sphere
	loop @B

	ret
MapDistProc endp

;******************************************************************************
; Calculate a ray from origin `RayOrg` and towards the direction `RayDir` that
; casts to the scene. Returns the cast point coordinates `MapCast` and the
; distance to the origin of the ray and the surface normal from the scene.
;******************************************************************************
MapCastProc proc

;	lea bx, gCastDistWithSpheres
;	assume bx:ptr tCastDistWithSpheres

	fldz
	fst  [bx].M.MapCast.D
	fst  [bx].M.MapCast.N.x
	fst  [bx].M.MapCast.N.y
	fstp [bx].M.MapCast.N.z

; Stepping the point to go forward
	mov cx, MapCast_Iterate
LoopIterate:
	fld [bx].M.Ray.O.x 
	fld [bx].M.Ray.dir.Ray.x
	fmul [bx].M.MapCast.D
	fadd
	fstp [bx].M.MapDist.O.x

	fld [bx].M.Ray.O.y 
	fld [bx].M.Ray.dir.Ray.y
	fmul [bx].M.MapCast.D
	fadd
	fstp [bx].M.MapDist.O.y

	fld [bx].M.Ray.O.z 
	fld [bx].M.Ray.dir.Ray.z
	fmul [bx].M.MapCast.D
	fadd
	fstp [bx].M.MapDist.O.z

	call IsAwayFromBB
	jnc InsideBB

	fld [bx].M.Ray.dir.Ray.y
	fldz
	fcompp
	fstsw ax
	sahf
	jbe ToSky
	
	; Hit the ground outside the bounding box
	fld1
	fstp [bx].M.MapCast.N.y

	fld [bx].M.Ray.O.y
	fldz
	fsub [bx].M.Ray.dir.Ray.y
	fdiv
	fstp [bx].M.MapCast.D

	call SetCastCrd

	mov [bx].M.MapCast.I, -1
	stc
	jmp done
ToSky:
; The origin of the ray is from outside of the bounding box and it's going to the sky

	fld [bx].M.MapDist.O.x
	fstp [bx].M.MapCast.O.x
	fld [bx].M.MapDist.O.y
	fstp [bx].M.MapCast.O.y
	fld [bx].M.MapDist.O.z
	fstp [bx].M.MapCast.O.z
	mov [bx].M.MapCast.I, -2
	clc
	jmp done

; The origin of the ray is inside the bounding box
InsideBB:
	push cx
	call MapDistProc
	pop cx

	fld [bx].M.MapDist.D
	fcomp [bx].Data_.DistEpsilon;[DistEpsilon]
	fstsw ax
	sahf
	ja NotNearEnough

	mov ax, [bx].M.MapDist.I
	mov [bx].M.MapCast.I, ax
	cmp ax, 0
	jge NotHitGround

	; Hit the ground inside the bounding box
	fld1
	fstp [bx].M.MapCast.N.y

	fld [bx].M.MapDist.O.x
	fstp [bx].M.MapCast.O.x
	fld [bx].M.MapDist.O.y
	fstp [bx].M.MapCast.O.y
	fld [bx].M.MapDist.O.z
	fstp [bx].M.MapCast.O.z
	stc
	jmp done

; Should iterate again
NotNearEnough:
	fld [bx].M.MapCast.D
	fadd [bx].M.MapDist.D
	fstp [bx].M.MapCast.D
	dec cx
	jcxz ExitIterate
	jmp LoopIterate

; Hit the spheres
NotHitGround:

	mul [bx].Data_.SizeOf_Sphere;[SizeOf_Sphere]
	mov si,ax
	
	; Calculate the normal
	fld [bx].M.MapDist.O.x
	fsub [si][bx].S.Position.x
	fst [bx].M.MapCast.N.x
	fmul st(0),st(0)
	fld [bx].M.MapDist.O.y
	fsub [si][bx].S.Position.y
	fst [bx].M.MapCast.N.y
	fmul st(0),st(0)
	fadd
	fld [bx].M.MapDist.O.z
	fsub [si][bx].S.Position.z
	fst [bx].M.MapCast.N.z
	fmul st(0),st(0)
	fadd
	fsqrt ; Normalize the normal
	fld st(0)
	fld [bx].M.MapCast.N.x
	fdivr
	fstp [bx].M.MapCast.N.x
	fld st(0)
	fld [bx].M.MapCast.N.y
	fdivr
	fstp [bx].M.MapCast.N.y
	fdivr [bx].M.MapCast.N.z
	fstp [bx].M.MapCast.N.z

	; Set cast coord
	fld [bx].M.MapDist.O.x
	fstp [bx].M.MapCast.O.x
	fld [bx].M.MapDist.O.y
	fstp [bx].M.MapCast.O.y
	fld [bx].M.MapDist.O.z
	fstp [bx].M.MapCast.O.z
	stc
	jmp done

; Finished iteration
ExitIterate:
	fld [bx].M.MapDist.O.x
	fstp [bx].M.MapCast.O.x
	fld [bx].M.MapDist.O.y
	fstp [bx].M.MapCast.O.y
	fld [bx].M.MapDist.O.z
	fstp [bx].M.MapCast.O.z
	mov [bx].M.MapCast.I, -2
	clc
done:

	ret
MapCastProc endp

; Subroutine: MapCast = RayOrg + RayDir * Dist
SetCastCrd proc


	fld [bx].M.Ray.O.x
	fld [bx].M.Ray.dir.Ray.x
	fmul [bx].M.MapCast.D
	fadd
	fstp [bx].M.MapCast.O.x

	fld [bx].M.Ray.O.y
	fld [bx].M.Ray.dir.Ray.y
	fmul [bx].M.MapCast.D
	fadd
	fstp [bx].M.MapCast.O.y

	fld [bx].M.Ray.O.z
	fld [bx].M.Ray.dir.Ray.z
	fmul [bx].M.MapCast.D
	fadd
	fstp [bx].M.MapCast.O.z
	

	ret
SetCastCrd endp	

;******************************************************************************
; Check if the ray from the origin `RayOrg` towards the direction `RayDir` is
; going away from the bounding box
;******************************************************************************
IsAwayFromBB proc uses bx

	
	fld [bx].M.Ray.O.x
	fcomp [bx].BB.N.x; [BBneg.x]
	fstsw ax
	sahf
	
jae XNIsOK
	fld [bx].M.Ray.dir.Ray.x
	fcomp [bx].Val_.FZero;[FZero]
	fstsw ax
	sahf
	
jae XNIsOK
	stc
	jmp done
	
XNIsOK:

	fld [bx].M.Ray.O.x
	fcomp [bx].BB.O.x;[BB.x]
	fstsw ax
	sahf
	
jbe XPIsOK
	fld [bx].M.Ray.dir.Ray.x
	fcomp [bx].Val_.FZero;[FZero]
	fstsw ax
	sahf
	
jbe XPIsOK
	stc
	jmp done
	
XPIsOK:
	
	fld [bx].M.Ray.O.y
	fcomp  [bx].BB.N.y;[BBneg.y]
	fstsw ax
	sahf
	
jae YNIsOK
	fld [bx].M.Ray.dir.Ray.y
	fcomp [bx].Val_.FZero;[FZero]
	fstsw ax
	sahf
jae YNIsOK
	stc
	jmp done
YNIsOK:

	fld [bx].M.Ray.O.y
	fcomp [bx].BB.O.y;[BB.y]
	fstsw ax
	sahf
	
jbe YPIsOK

	fld [bx].M.Ray.dir.Ray.y
	fcomp [bx].Val_.FZero; [FZero]
	fstsw ax
	sahf
jbe YPIsOK
	stc
	jmp done
YPIsOK:

	fld [bx].M.Ray.O.z
	fcomp [bx].BB.N.z; [BBneg.z]
	fstsw ax
	sahf
	
jae ZNIsOK
	fld [bx].M.Ray.dir.Ray.z
	fcomp [bx].Val_.FZero;[FZero]
	fstsw ax
	sahf
	
jae ZNIsOK
	stc
	jmp done
	
ZNIsOK:

	fld [bx].M.Ray.O.z
	fcomp [bx].BB.O.z;[BB.z]
	fstsw ax
	sahf
jbe ZPIsOK

	fld [bx].M.Ray.dir.Ray.z
	fcomp [bx].Val_.FZero;[FZero]
	fstsw ax
	sahf
jbe ZPIsOK
	stc
	jmp done
	
ZPIsOK:

	clc
done:

	ret
IsAwayFromBB endp
	
;******************************************************************************
; Render the pixel by a given ray from the origin `RayOrg` towards the
; direction `RayDir`
;******************************************************************************
RenderScene proc uses si
	
	fld1
	fst  [bx].Mask_.R
	fst  [bx].Mask_.G
	fstp [bx].Mask_.B
	fld  [bx].Cam.x
	fstp [bx].M.Ray.O.x
	fld  [bx].Cam.y
	fstp  [bx].M.Ray.O.y
	fld  [bx].Cam.z
	fstp  [bx].M.Ray.O.z

	mov cx, SampleDepth
LoopSampling:
	push cx
	call MapCastProc
	pop cx
;.if !CARRY?	
	jc CastSphereOrGround

; If not cast then still step forward
NotCast:
	fld [bx].M.MapCast.O.x
	fstp [bx].M.Ray.O.x
	fld [bx].M.MapCast.O.y
	fstp [bx].M.Ray.O.y
	fld [bx].M.MapCast.O.z
	fstp [bx].M.Ray.O.z

	dec cx
	jcxz Finished1
	jmp LoopSampling

Finished1:
	jmp Finished

; If cast to the spheres or the ground, do coloring
CastSphereOrGround:
	mov ax, [bx].M.MapCast.I
	cmp ax, 0
	jl CastGround

	; Casting spheres
	mul [bx].Data_.SizeOf_Sphere
	mov si,ax
	
	fld [bx].Mask_.R
	fmul [si][bx].S.Color.R
	fstp [bx].Mask_.R
	fld [bx].Mask_.G
	fmul [si][bx].S.Color.G
	fstp [bx].Mask_.G
	fld [bx].Mask_.B
	fmul [si][bx].S.Color.B
	fstp [bx].Mask_.B

	; Reflection
	fld [bx].M.MapCast.N.x
	fmul [bx].M.Ray.dir.Ray.x
	fld [bx].M.MapCast.N.y
	fmul [bx].M.Ray.dir.Ray.y
	fadd
	fld [bx].M.MapCast.N.z
	fmul [bx].M.Ray.dir.Ray.z
	fadd
	fadd st(0),st(0) ; (Normal dot Ray) * 2
	
	fld st(0)
	fmul [bx].M.MapCast.N.x
	fsubr [bx].M.Ray.dir.Ray.x
	fstp [bx].M.Ray.dir.Ray.x
	
	fld st(0)
	fmul [bx].M.MapCast.N.y
	fsubr [bx].M.Ray.dir.Ray.y
	fstp [bx].M.Ray.dir.Ray.y

	fmul [bx].M.MapCast.N.z
	fsubr [bx].M.Ray.dir.Ray.z
	fstp [bx].M.Ray.dir.Ray.z

	call SetRayOrg

	dec cx
	jcxz Finished
	jmp LoopSampling
;.endif

; The ray is casting the ground
CastGround:
	fld [bx].M.MapCast.O.x
	fadd st(0),st(0)
	fistp [bx].Data_.TempW;[TempW]
	fwait
	mov ax, [bx].Data_.TempW;[TempW]
	fld  [bx].M.MapCast.O.z
	fadd st(0),st(0)
	fistp [bx].Data_.TempW; [TempW]
	fwait
	xor ax,[bx].Data_.TempW; [TempW]
	test ax, 1
	jz GroundColorPattern

	fld  [bx].Mask_.R
	fmul [bx].Val_.F05;[F05]
	fstp [bx].Mask_.R
	fld  [bx].Mask_.G
	fmul [bx].Val_.F05;[F05]
	fstp [bx].Mask_.G
	fld  [bx].Mask_.B
	fmul [bx].Val_.F05;[F05]
	fstp [bx].Mask_.B

GroundColorPattern:
	fld [bx].M.Ray.dir.Ray.y
	fabs
	fstp [bx].M.Ray.dir.Ray.y

	call SetRayOrg

	dec cx
	jcxz Finished
	jmp LoopSampling

; Finished iteration
Finished:
	call GetSkyColor
	fld [bx].Mix.GetSkyColor.R
	fmul [bx].Mask_.R
	fimul [bx].Val_.C255;[C255]
	fistp [bx].P.Col.R
	fld [bx].Mix.GetSkyColor.G
	fmul [bx].Mask_.G
	fimul [bx].Val_.C255;[C255]
	fistp [bx].P.Col.G
	fld [bx].Mix.GetSkyColor.B
	fmul[bx].Mask_.B
	fimul [bx].Val_.C255;[C255]
	fistp [bx].P.Col.B
	fwait

; Clamp the color not to overflow
	cmp [bx].P.Col.R, 255
	jle R_OK
	mov [bx].P.Col.R, 255
R_OK:
	cmp [bx].P.Col.G, 255
	jle G_OK
	mov [bx].P.Col.G, 255
G_OK:
	cmp [bx].P.Col.B, 255
	jle B_OK
	mov [bx].P.Col.B, 255
B_OK:
	

	call PickColor
	
	ret
RenderScene endp

; When cast, set the ray origin near the cast point
SetRayOrg proc

	fld  [bx].M.MapCast.O.x
	fld  [bx].M.Ray.dir.Ray.x
	fmul [bx].Data_.DistEpsilon2; [DistEpsilon2]
	fadd
	fstp  [bx].M.Ray.O.x
	
	fld  [bx].M.MapCast.O.y
	fld  [bx].M.Ray.dir.Ray.y
	fmul [bx].Data_.DistEpsilon2; [DistEpsilon2]
	fadd
	fstp [bx].M.Ray.O.y

	fld  [bx].M.MapCast.O.z
	fld  [bx].M.Ray.dir.Ray.z
	fmul [bx].Data_.DistEpsilon2; [DistEpsilon2]
	fadd
	fstp [bx].M.Ray.O.z

	ret 
SetRayOrg endp

;std
;end start

;shellcode
end _entry