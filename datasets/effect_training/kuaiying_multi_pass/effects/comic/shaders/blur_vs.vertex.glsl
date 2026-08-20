#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;

varying vec2 textureCoord;
varying vec4 coord1;
varying vec4 coord2;
varying vec4 coord3;

uniform vec2 offset;
//vec2 textureSize = vec2(360.,640.);
//vec2 textelSize = vec2(1.0/180.,1.0/320.);
vec2 textelSize = vec2(1./180.,1./320.);
void main()
{
    textureCoord = position*.5+.5;
    gl_Position = vec4(position, 0.,1.);

    coord1 = textureCoord.xyxy + offset.xyxy * vec4(1.,1.,-1.,-1.) * textelSize.xyxy;
    coord2 = textureCoord.xyxy + offset.xyxy * vec4(2.,2.,-2.,-2.) * textelSize.xyxy;
    coord3 = textureCoord.xyxy + offset.xyxy * vec4(3.,3.,-3.,-3.) * textelSize.xyxy;
}
