#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

    uniform sampler2D inputImageTexture;
    varying vec2 vUV0;
    void main()
    {
        vec4 outputColor = texture2D(inputImageTexture,vUV0);
//        outputColor.r = 1.0;
        gl_FragColor = outputColor;
    }
