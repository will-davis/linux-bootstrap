" Shadertoy host uniforms — provided by the Shadertoy runtime (and our
" rpi4 shadertoy renderer), not by the GLSL language itself, so the stock
" $VIMRUNTIME/syntax/glsl.vim leaves them unhighlighted.
"
" Lives in after/syntax/ so it runs *after* the stock syntax file and
" extends it instead of replacing it.
syn keyword glslShadertoy iResolution iTime iTimeDelta
syn keyword glslShadertoy iFrame iFrameRate iMouse iDate
syn keyword glslShadertoy iChannel0 iChannel1 iChannel2 iChannel3
syn keyword glslShadertoy iChannelTime iChannelResolution
syn keyword glslShadertoy iSampleRate mainImage

hi def link glslShadertoy Special
