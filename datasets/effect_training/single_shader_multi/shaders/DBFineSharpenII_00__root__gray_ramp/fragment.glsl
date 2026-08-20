precision highp float;


uniform float uProgress;
uniform float uTime;
varying vec2 textureCoordinate;
uniform sampler2D inputImageTexture;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define width 1080.0
#define height 1080.0
#define blurRatio (0.05 + 2.0 * uProgress)
void main()
{ 
   // vec2 x_y= u_ScreenParams.xy;
   vec2 x_y = vec2(width, height);
   vec2 curCoord=textureCoordinate*x_y;
   vec4 originalColor=texture2D(inputImageTexture,textureCoordinate); 
   vec3 color_output=originalColor.rgb; 
   float alpha_mask = 1.;
   // if (alpha_mask > .1)
   {
     float radius=6.0 * blurRatio;
   //   if (r > 0.0) radius = r;
     vec3 color_pow_sum=originalColor.rgb;
     vec3 weight_pow_sum=pow(color_pow_sum.rgb,vec3(2.0));
     weight_pow_sum=clamp(weight_pow_sum,vec3(0.001),vec3(1.0));
     color_pow_sum=color_pow_sum*weight_pow_sum;
     vec2 x_range=vec2(clamp(curCoord.x-radius*alpha_mask,0.0,x_y.x),clamp(curCoord.x+radius*alpha_mask,0.0,x_y.x));
     vec2 y_range=vec2(clamp(curCoord.y-radius*alpha_mask,0.0,x_y.y),clamp(curCoord.y+radius*alpha_mask,0.0,x_y.y));
     for(int x=-12;x<=12;x++) // Dealing with Compatibility issues
     {
        if(float(x)<-radius || float(x)>radius) continue;
        float i = clamp(curCoord.x+float(x),0.0,x_y.x);
        for(int y=-12;y<=12;y++)
        {
            if(float(y)<-radius || float(y)>radius) continue;
            float j = clamp(curCoord.y+float(y),0.0,x_y.y);
            vec2 currentCoord = vec2(i,j);
            float si = (i-x_range.x)/(x_range.y-x_range.x+0.0001);
            float sj = (j-y_range.x)/(y_range.y-y_range.x+0.0001);
            vec2 spotCoord = vec2(si,sj);
            if (abs(spotCoord.x - .5) < .7 * .7 - pow((spotCoord.y - .5) * 1.4, 2.))
            {
               vec3 curColor = texture2D(inputImageTexture,currentCoord/x_y).rgb;
               vec3 curWeight = pow(curColor,vec3(4.0));
               weight_pow_sum += curWeight;
               color_pow_sum += curWeight*curColor;
            }
        }
     }
     
   //   for(float i=x_range.x;i<=x_range.y;i+=1.0)
   //   {
   //      for(float j=y_range.x;j<=y_range.y;j+=1.0)
   //      {
   //           vec2 currentCoord = vec2(i,j);
   //           float si = (i-x_range.x)/(x_range.y-x_range.x);
   //           float sj = (j-y_range.x)/(y_range.y-y_range.x);
   //           vec2 spotCoord = vec2(si,sj);
   //           if (abs(spotCoord.x - .5) < .7 * .7 - pow((spotCoord.y - .5) * 1.4, 2.))
   //           {
   //              vec3 curColor = texture2D(inputImageTexture,currentCoord/x_y).rgb;
   //              vec3 curWeight = pow(curColor,vec3(4.0));
   //              weight_pow_sum += curWeight;
   //              color_pow_sum += curWeight*curColor;
   //           }
   //      }
   //   }
     color_output=color_pow_sum/weight_pow_sum; 
   }
   gl_FragColor = vec4(color_output,originalColor.a);
}
