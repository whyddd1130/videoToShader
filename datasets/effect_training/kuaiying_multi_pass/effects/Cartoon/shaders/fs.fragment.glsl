#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D originImage;

uniform float steps;
uniform float smoothness;

void main() 
{
    vec4 color = texture2D(inputImageTexture, textureCoord);
    vec3 coefficients = vec3(0.2126, 0.7152, 0.0722);
    float grey = dot(coefficients, color.rgb);

    float brightness = 0.9;
    grey = clamp(grey * brightness, 0.0, 1.0);

    float levels = steps - 1.0;
    float posterized = floor(grey * levels + 0.5) / levels;

    //float contrast = 1.3;
    //float contrasted = clamp(contrast * (posterized - 0.5) + 0.5, 0.0, 1.0);

    float r = clamp(color.r * posterized / grey, 0.0, 1.0);
    float g = clamp(color.g * posterized / grey, 0.0, 1.0);
    float b = clamp(color.b * posterized / grey, 0.0, 1.0);

    vec4 originColor = texture2D(inputImageTexture, textureCoord);
    r = mix(r, originColor.r, smoothness);
    g = mix(g, originColor.g, smoothness);
    b = mix(b, originColor.b, smoothness);

    gl_FragColor = vec4(r, g, b, color.a);
}
