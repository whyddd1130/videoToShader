#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
uniform vec2 u_size;
uniform float u_degree;

varying vec2 blurCoordinates[13];

void main()
{
    gl_Position = vec4(position, 0.0, 1.0);
    
    int multiplier = 0;
    vec2 blurStep;
    float offset = u_degree * 0.005;
    vec2 singleStepOffset = vec2(offset, 0.0);
    
    for (int i = 0; i < 13; i++)
    {
        blurStep = float(-i) * singleStepOffset;
        blurCoordinates[i] = (position * 0.5 + 0.5) + blurStep;
    }
}
