#version 460 compatibility

in vec2 texcoord;

uniform vec2 texelSize;
uniform sampler2D colortex11;

/* RENDERTARGETS: 12 */
//layout(location = 0) out vec4 color;

void main()
{
    vec2 tc = gl_FragCoord.xy * texelSize;
    vec4 albedo3 = texture2D(colortex11, tc);

    //color = albedo3;
    gl_FragData[0] = albedo3;
}
