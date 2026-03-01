#version 460 compatibility

in vec4 color;
in vec4 lmtexcoord;

uniform sampler2D gtexture;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outcolor;
void main()
{
    vec4 albedo = texture(gtexture, lmtexcoord.xy) * color;
    if (albedo.a < 0.00001)
	{
		discard;
	}
    outcolor = albedo;
}