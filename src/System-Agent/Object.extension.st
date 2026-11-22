!Object methodsFor: '*System-Agent'!
pngBytes
	"PNG bytes for the agent to see, or nil."
	^nil
!
pngBytesScaledToFit: maxEdge pixels: maxPixels
	"PNG bytes for the agent to see, at most maxEdge pixels on the longer side and maxPixels in area, or nil (Form scales itself down)."
	^self pngBytes
! !
