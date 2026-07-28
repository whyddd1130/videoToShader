
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
varying vec2 uv;
varying vec2 uv0;
varying vec2 v_uv;
varying vec2 textureCoord;
varying vec2 texCoord;
varying vec2 textureCoordinate;
varying vec2 uRenderSize;

void main()
{
    vec2 t = position * 0.5 + 0.5;
    uv = t;
    uv0 = t;
    v_uv = t;
    textureCoord = t;
    texCoord = t;
    textureCoordinate = t;
    uRenderSize = vec2(1080.0, 1080.0);
    gl_Position = vec4(position, 0.0, 1.0);
}

]]

local fs = [[
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

]]

ShaderLaba7efddf0bcb8 = {}

function ShaderLaba7efddf0bcb8:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLaba7efddf0bcb8' == effectId
end

function ShaderLaba7efddf0bcb8.createWithId(effectId)
    if not ShaderLaba7efddf0bcb8:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLaba7efddf0bcb8)
    o:init()
    return o
end

function ShaderLaba7efddf0bcb8:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLaba7efddf0bcb8:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLaba7efddf0bcb8:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLaba7efddf0bcb8:resize(width, height)
end

function ShaderLaba7efddf0bcb8:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLaba7efddf0bcb8:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLaba7efddf0bcb8:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLaba7efddf0bcb8:onDestroy()
end
