attribute vec2 position; varying vec2 textureCoord; void main(){textureCoord=position*.5+.5;gl_Position=vec4(position,0.,1.);}
