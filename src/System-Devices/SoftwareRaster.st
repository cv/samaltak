Object subclass: #SoftwareRaster
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Devices'!

SoftwareRaster comment: 'I am the pixel work of a software GPU, the raster primitives (PlatformRaster in the VM, docs/platform.md): the Renderer''s uber-shader run on a batch of its vertices, fills, blits, and copies of pixel rectangles, on memory at addresses (Machine allocate:). A surface is {address. width. height. format}, formats and blend modes the gpu primitives'' codes (1 r8, 2 rgba8, 3 bgra8; 0 none, 1 alpha, 2 premultiplied). SoftwareGPU draws with me, FirmwareScreen presents.'!

!SoftwareRaster class methodsFor: 'drawing'!
draw: aState vertices: address first: first count: count
	"Run the Renderer's pipeline on its vertices first .. first + count - 1 (40 bytes each) at address. aState: {target. width. height. format. blend. scissorX. scissorY. scissorW. scissorH. viewportX. viewportY. viewportW. viewportH. viewSizeX. viewSizeY. translateX. translateY. texture (0: none). textureWidth. textureHeight. textureFormat. linear. repeat}."
	<primitive: 'rasterDraw'>
	^self error: 'bad draw'
!
fill: address count: n bytesPerPixel: bpp value: anInteger
	"n pixels of bpp bytes (1 or 4) set to anInteger."
	<primitive: 'rasterFill'>
	^self error: 'bad fill'
!
blit: sourceSurface rect: sourceRect to: destinationSurface rect: destinationRect linear: aBoolean
	"Rects {x. y. w. h}: each destination pixel samples the source at its centre mapped into sourceRect (nearest or linear, clamped to the edge), converted to the destination's format."
	<primitive: 'rasterBlit'>
	^self error: 'bad blit'
!
quadBoundsOf: vertices from: firstQuad count: n into: aByteArray
	"The device pixels that quads firstQuad .. firstQuad + n - 1 of a DisplayList's vertex bytes cover, as int32 x0 y0 x1 y1 (floored and ceiled) in aByteArray's first 16 bytes: true, false if n is 0, nil if the VM cannot (an older one)."
	<primitive: 'rasterQuadBounds'>
	^nil
!
copy: destination stride: destinationStride from: source stride: sourceStride width: w height: h bytesPerPixel: bpp mode: mode
	"h rows of w pixels of bpp bytes (1 or 4); destination and source are addresses or byte objects (Bitmaps). mode bit 1 swaps red and blue, bit 2 copies only the pixels whose alpha is not 0."
	<primitive: 'rasterCopy'>
	^self error: 'bad copy'
! !
