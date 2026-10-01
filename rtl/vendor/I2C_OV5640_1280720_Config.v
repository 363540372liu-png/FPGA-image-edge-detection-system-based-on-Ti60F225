/*-------------------------------------------------------------------------
This confidential and proprietary software may be only used as authorized
by a licensing agreement from CrazyBingo.www.cnblogs.com/crazybingo
(C) COPYRIGHT 2012 CrazyBingo. ALL RIGHTS RESERVED
Filename			:		I2C_OV5640_1280720_Config.v
Author				:		CrazyBingo
Date				:		2019-08-03
Version				:		1.0
Description			:		I2C Configure Data of OV5640.
Modification History	:
Date			By			Version			Change Description
===========================================================================
19/08/03		CrazyBingo	1.0				Original
--------------------------------------------------------------------------*/

`timescale 1ns/1ns
module	I2C_OV5640_1280720_Config #(		//1280*720@60 with AutO/Manual Exposure
  parameter IMAGE_WIDTH  = 16'd1280,
            IMAGE_HEIGHT = 16'd720,
            IMAGE_FLIP   = 8'h40,
            IMAGE_MIRROR = 4'h7
)
(
	input		[7:0]	LUT_INDEX,
	output	reg	[23:0]	LUT_DATA,
	output		[7:0]	LUT_SIZE
);
`define PLL_EN
`define AE_EN

assign	LUT_SIZE = 1'b1 + 8'd251 ;

//-----------------------------------------------------------------
/////////////////////	Config Data LUT	  //////////////////////////	
always@(*)
begin
	case(LUT_INDEX)
0 :     LUT_DATA    =   24'h3103_11;	// system clock from pad, bit[1]	
1 :     LUT_DATA    =   24'h3008_82;	// software reset, bit[7]	
   	//delay 5ms		
2 :     LUT_DATA    =   24'h3008_42;	// software power down, bit[6]	
3 :     LUT_DATA    =   24'h3103_03;	// system clock from PLL, bit[1]	
4 :     LUT_DATA    =   24'h3017_ff;	// FREX, Vsync, HREF, PCLK, D[9:6] output enable	
5 :     LUT_DATA    =   24'h3018_ff;	// D[5:0], GPIO[1:0] output enable	
6 :     LUT_DATA    =   24'h3034_1a;	// MIPI 10-bit	
7 :     LUT_DATA    =   24'h3037_13;	// PLL root divider, bit[4], PLL pre-divider, bit[3:0]	
8 :     LUT_DATA    =   24'h3108_01;	// PCLK root divider, bit[5:4], SCLK2x root divider, bit[3:2]	
9 :     LUT_DATA    =   24'h3630_36;	// SCLK root divider, bit[1:0]	
10:     LUT_DATA    =   24'h3631_0e;		
11:     LUT_DATA    =   24'h3632_e2;		
12:     LUT_DATA    =   24'h3633_12;		
13:     LUT_DATA    =   24'h3621_e0;		
14:     LUT_DATA    =   24'h3704_a0;		
15:     LUT_DATA    =   24'h3703_5a;		
16:     LUT_DATA    =   24'h3715_78;		
17:     LUT_DATA    =   24'h3717_01;		
18:     LUT_DATA    =   24'h370b_60;		
19:     LUT_DATA    =   24'h3705_1a;		
20:     LUT_DATA    =   24'h3905_02;		
21:     LUT_DATA    =   24'h3906_10;		
22:     LUT_DATA    =   24'h3901_0a;		
23:     LUT_DATA    =   24'h3731_12;		
24:     LUT_DATA    =   24'h3600_08;	// VCM control	
25:     LUT_DATA    =   24'h3601_33;	// VCM control	
26:     LUT_DATA    =   24'h302d_60;	// system control	
27:     LUT_DATA    =   24'h3620_52;		
28:     LUT_DATA    =   24'h371b_20;		
29:     LUT_DATA    =   24'h471c_50;		
30:     LUT_DATA    =   24'h3a13_43;	// pre-gain =	1.047x
31:     LUT_DATA    =   24'h3a18_00;	// gain ceiling	
32:     LUT_DATA    =   24'h3a19_f8;	// gain ceiling =	15.5x
33:     LUT_DATA    =   24'h3635_13;		
34:     LUT_DATA    =   24'h3636_03;		
35:     LUT_DATA    =   24'h3634_40;		
36:     LUT_DATA    =   24'h3622_01;		
   	// 50/60Hz detection 50/60Hz 灯光条纹过滤		
37:     LUT_DATA    =   24'h3c01_34;	// Band auto, bit[7]	
38:     LUT_DATA    =   24'h3c04_28;	// threshold low sum	
39:     LUT_DATA    =   24'h3c05_98;	// threshold high sum	
40:     LUT_DATA    =   24'h3c06_00;	// light meter 1 threshold[15:8]	
41:     LUT_DATA    =   24'h3c07_08;	// light meter 1 threshold[7:0]	
42:     LUT_DATA    =   24'h3c08_00;	// light meter 2 threshold[15:8]	
43:     LUT_DATA    =   24'h3c09_1c;	// light meter 2 threshold[7:0]	
44:     LUT_DATA    =   24'h3c0a_9c;	// sample number[15:8]	
45:     LUT_DATA    =   24'h3c0b_40;	// sample number[7:0]	
46:     LUT_DATA    =   24'h3810_00;	// Timing Hoffset[11:8]	
47:     LUT_DATA    =   24'h3811_10;	// Timing Hoffset[7:0]	
48:     LUT_DATA    =   24'h3812_00;	// Timing Voffset[10:8]	
49:     LUT_DATA    =   24'h3708_64;		
50:     LUT_DATA    =   24'h4001_02;	// BLC start from line 2	
51:     LUT_DATA    =   24'h4005_1a;	// BLC always update	
52:     LUT_DATA    =   24'h3000_00;	// enable blocks	
53:     LUT_DATA    =   24'h3004_ff;	// enable clocks	
54:     LUT_DATA    =   24'h300e_58;	// MIPI power down, DVP enable	
55:     LUT_DATA    =   24'h302e_00;		
56:     LUT_DATA    =   24'h4300_61; 	//	RGB. 	00;	// Bayer BGBG  	//h4300_6f(千兆网模式)--------------------------------------------------------
57:     LUT_DATA    =   24'h501f_01;	//	RGB	03;	// Bayer	
58:     LUT_DATA    =   24'h440e_00;		
59:     LUT_DATA    =   24'h5000_a7;	// Lenc on, raw gamma on, BPC on, WPC on, CIP on	
   	// AEC target 自动曝光控制		
60:     LUT_DATA    =   24'h3a0f_30;	// stable range in high	
61:     LUT_DATA    =   24'h3a10_28;	// stable range in low	
62:     LUT_DATA    =   24'h3a1b_30;	// stable range out high	
63:     LUT_DATA    =   24'h3a1e_26;	// stable range out low	
64:     LUT_DATA    =   24'h3a11_60;	// fast zone high	
65:     LUT_DATA    =   24'h3a1f_14;	// fast zone low	
   	// Lens correction for ? 镜头补偿		
66 :     LUT_DATA    =   24'h5800_23;		
67 :     LUT_DATA    =   24'h5801_14;		
68 :     LUT_DATA    =   24'h5802_0f;		
69 :     LUT_DATA    =   24'h5803_0f;		
70 :     LUT_DATA    =   24'h5804_12;		
71 :     LUT_DATA    =   24'h5805_26;		
72 :     LUT_DATA    =   24'h5806_0c;		
73 :     LUT_DATA    =   24'h5807_08;		
74 :     LUT_DATA    =   24'h5808_05;		
75 :     LUT_DATA    =   24'h5809_05;		
76 :     LUT_DATA    =   24'h580a_08;		
77 :     LUT_DATA    =   24'h580b_0d;		
78 :     LUT_DATA    =   24'h580c_08;		
79 :     LUT_DATA    =   24'h580d_03;		
80 :     LUT_DATA    =   24'h580e_00;		
81 :     LUT_DATA    =   24'h580f_00;		
82 :     LUT_DATA    =   24'h5810_03;		
83 :     LUT_DATA    =   24'h5811_09;		
84 :     LUT_DATA    =   24'h5812_07;		
85 :     LUT_DATA    =   24'h5813_03;		
86 :     LUT_DATA    =   24'h5814_00;		
87 :     LUT_DATA    =   24'h5815_01;		
88 :     LUT_DATA    =   24'h5816_03;		
89 :     LUT_DATA    =   24'h5817_08;		
90 :     LUT_DATA    =   24'h5818_0d;		
91 :     LUT_DATA    =   24'h5819_08;		
92 :     LUT_DATA    =   24'h581a_05;		
93 :     LUT_DATA    =   24'h581b_06;		
94 :     LUT_DATA    =   24'h581c_08;		
95 :     LUT_DATA    =   24'h581d_0e;		
96 :     LUT_DATA    =   24'h581e_29;		
97 :     LUT_DATA    =   24'h581f_17;		
98 :     LUT_DATA    =   24'h5820_11;		
99 :     LUT_DATA    =   24'h5821_11;		
100:     LUT_DATA    =   24'h5822_15;		
101:     LUT_DATA    =   24'h5823_28;		
102:     LUT_DATA    =   24'h5824_46;		
103:     LUT_DATA    =   24'h5825_26;		
104:     LUT_DATA    =   24'h5826_08;		
105:     LUT_DATA    =   24'h5827_26;		
106:     LUT_DATA    =   24'h5828_64;		
107:     LUT_DATA    =   24'h5829_26;		
108:     LUT_DATA    =   24'h582a_24;		
109:     LUT_DATA    =   24'h582b_22;		
110:     LUT_DATA    =   24'h582c_24;		
111:     LUT_DATA    =   24'h582d_24;		
112:     LUT_DATA    =   24'h582e_06;		
113:     LUT_DATA    =   24'h582f_22;		
114:     LUT_DATA    =   24'h5830_40;		
115:     LUT_DATA    =   24'h5831_42;		
116:     LUT_DATA    =   24'h5832_24;		
117:     LUT_DATA    =   24'h5833_26;		
118:     LUT_DATA    =   24'h5834_24;		
119:     LUT_DATA    =   24'h5835_22;		
120:     LUT_DATA    =   24'h5836_22;		
121:     LUT_DATA    =   24'h5837_26;		
122:     LUT_DATA    =   24'h5838_44;		
123:     LUT_DATA    =   24'h5839_24;		
124:     LUT_DATA    =   24'h583a_26;		
125:     LUT_DATA    =   24'h583b_28;		
126:     LUT_DATA    =   24'h583c_42;		
127:     LUT_DATA    =   24'h583d_ce;	// lenc BR offset	
   	// AWB 自动白平衡		
128:     LUT_DATA    =   24'h5180_ff;	// AWB B block	
129:     LUT_DATA    =   24'h5181_f2;	// AWB control	
130:     LUT_DATA    =   24'h5182_00;	// [7:4] max local counter, [3:0] max fast counter	
131:     LUT_DATA    =   24'h5183_14;	// AWB advanced	
132:     LUT_DATA    =   24'h5184_25;		
133:     LUT_DATA    =   24'h5185_24;		
134:     LUT_DATA    =   24'h5186_09;		
135:     LUT_DATA    =   24'h5187_09;		
136:     LUT_DATA    =   24'h5188_09;		
137:     LUT_DATA    =   24'h5189_75;		
138:     LUT_DATA    =   24'h518a_54;		
139:     LUT_DATA    =   24'h518b_e0;		
140:     LUT_DATA    =   24'h518c_b2;		
141:     LUT_DATA    =   24'h518d_42;		
142:     LUT_DATA    =   24'h518e_3d;		
143:     LUT_DATA    =   24'h518f_56;		
144:     LUT_DATA    =   24'h5190_46;		
145:     LUT_DATA    =   24'h5191_f8;	// AWB top limit	
146:     LUT_DATA    =   24'h5192_04;	// AWB bottom limit	
147:     LUT_DATA    =   24'h5193_70;	// red limit	
148:     LUT_DATA    =   24'h5194_f0;	// green limit	
149:     LUT_DATA    =   24'h5195_f0;	// blue limit	
150:     LUT_DATA    =   24'h5196_03;	// AWB control	
151:     LUT_DATA    =   24'h5197_01;	// local limit	
152:     LUT_DATA    =   24'h5198_04;		
153:     LUT_DATA    =   24'h5199_12;		
154:     LUT_DATA    =   24'h519a_04;		
155:     LUT_DATA    =   24'h519b_00;		
156:     LUT_DATA    =   24'h519c_06;		
157:     LUT_DATA    =   24'h519d_82;		
158:     LUT_DATA    =   24'h519e_38;	// AWB control	
   	// Gamma 伽玛曲线		
159:     LUT_DATA    =   24'h5480_01;	// Gamma bias plus on, bit[0]	
160:     LUT_DATA    =   24'h5481_08;		
161:     LUT_DATA    =   24'h5482_14;		
162:     LUT_DATA    =   24'h5483_28;		
163:     LUT_DATA    =   24'h5484_51;		
164:     LUT_DATA    =   24'h5485_65;		
165:     LUT_DATA    =   24'h5486_71;		
166:     LUT_DATA    =   24'h5487_7d;		
167:     LUT_DATA    =   24'h5488_87;		
168:     LUT_DATA    =   24'h5489_91;		
169:     LUT_DATA    =   24'h548a_9a;		
170:     LUT_DATA    =   24'h548b_aa;		
171:     LUT_DATA    =   24'h548c_b8;		
172:     LUT_DATA    =   24'h548d_cd;		
173:     LUT_DATA    =   24'h548e_dd;		
174:     LUT_DATA    =   24'h548f_ea;		
175:     LUT_DATA    =   24'h5490_1d;		
   	// color matrix 色彩矩阵		
176:     LUT_DATA    =   24'h5381_1e;	// CMX1 for Y	
177:     LUT_DATA    =   24'h5382_5b;	// CMX2 for Y	
178:     LUT_DATA    =   24'h5383_08;	// CMX3 for Y	
179:     LUT_DATA    =   24'h5384_0a;	// CMX4 for U	
180:     LUT_DATA    =   24'h5385_7e;	// CMX5 for U	
181:     LUT_DATA    =   24'h5386_88;	// CMX6 for U	
182:     LUT_DATA    =   24'h5387_7c;	// CMX7 for V	
183:     LUT_DATA    =   24'h5388_6c;	// CMX8 for V	
184:     LUT_DATA    =   24'h5389_10;	// CMX9 for V	
185:     LUT_DATA    =   24'h538a_01;	// sign[9]	
186:     LUT_DATA    =   24'h538b_98;	// sign[8:1]	
   	// UV adjust UV 色彩饱和度调整		
187:     LUT_DATA    =   24'h5580_06;	// saturation on, bit[1]	
188:     LUT_DATA    =   24'h5583_40;		
189:     LUT_DATA    =   24'h5584_10;		
190:     LUT_DATA    =   24'h5589_10;		
191:     LUT_DATA    =   24'h558a_00;		
192:     LUT_DATA    =   24'h558b_f8;		
193:     LUT_DATA    =   24'h501d_40;	// enable manual offset of contrast	
   	// CIP 锐化和降噪		
194:     LUT_DATA    =   24'h5300_08;	// CIP sharpen MT threshold 1	
195:     LUT_DATA    =   24'h5301_30;	// CIP sharpen MT threshold 2	
196:     LUT_DATA    =   24'h5302_10;	// CIP sharpen MT offset 1	
197:     LUT_DATA    =   24'h5303_00;	// CIP sharpen MT offset 2	
198:     LUT_DATA    =   24'h5304_08;	// CIP DNS threshold 1	
199:     LUT_DATA    =   24'h5305_30;	// CIP DNS threshold 2	
200:     LUT_DATA    =   24'h5306_08;	// CIP DNS offset 1	
201:     LUT_DATA    =   24'h5307_16;	// CIP DNS offset 2	
202:     LUT_DATA    =   24'h5309_08;	// CIP sharpen TH threshold 1	
203:     LUT_DATA    =   24'h530a_30;	// CIP sharpen TH threshold 2	
204:     LUT_DATA    =   24'h530b_04;	// CIP sharpen TH offset 1	
205:     LUT_DATA    =   24'h530c_06;	// CIP sharpen TH offset 2	
206:     LUT_DATA    =   24'h5025_00;		
207:     LUT_DATA    =   24'h3008_02;	// wake up from standby, bit[6]	

	// 12824'h720, 30fps
	// input clock 24Mhz, PCLK 42Mhz
208:     LUT_DATA    = 24'h3035_21; // PLL  21:30fps  41:15fps  81:7.5fps
209:     LUT_DATA    = 24'h3036_69; // PLL
210:     LUT_DATA    = 24'h3c07_07; // lightmeter 1 threshold[7:0]
211:     LUT_DATA    = {16'h3820, IMAGE_FLIP}; // flip
212:     LUT_DATA    = {20'h38210, IMAGE_MIRROR}; // no mirror
213:     LUT_DATA    = 24'h3814_31; // timing X inc
214:     LUT_DATA    = 24'h3815_31; // timing Y inc
215:     LUT_DATA    = 24'h3800_00; // HS
216:     LUT_DATA    = 24'h3801_00; // HS
217:     LUT_DATA    = 24'h3802_00; // VS
218:     LUT_DATA    = 24'h3803_fa; // VS
219:     LUT_DATA    = 24'h3804_0a; // HW SET_OV5640 +  HE}
220:     LUT_DATA    = 24'h3805_3f; // HW SET_OV5640 +  HE}
221:     LUT_DATA    = 24'h3806_06; // VH SET_OV5640 +  VE}
222:     LUT_DATA    = 24'h3807_a9; // VH SET_OV5640 +  VE}
223:     LUT_DATA    = {16'h3808, IMAGE_WIDTH[15:8]}; // DVPHO  (<1280>500) (<640>280)IMAGE_WIDTH
224:     LUT_DATA    = {16'h3809, IMAGE_WIDTH[ 7:0]}; // DVPHO
225:     LUT_DATA    = {16'h380a, IMAGE_HEIGHT[15:8]}; // DVPVO  (<720>2d0)  (<480>1e0)IMAGE_HEIGHT
226:     LUT_DATA    = {16'h380b, IMAGE_HEIGHT[ 7:0]}; // DVPHO
227:     LUT_DATA    = 24'h380c_07; // HTS
228:     LUT_DATA    = 24'h380d_64; // HTS
229:     LUT_DATA    = 24'h380e_02; // VTS
230:     LUT_DATA    = 24'h380f_e4; // VTS
231:     LUT_DATA    = 24'h3813_04; // timing V offset
232:     LUT_DATA    = 24'h3618_00;
233:     LUT_DATA    = 24'h3612_29;
234:     LUT_DATA    = 24'h3709_52;
235:     LUT_DATA    = 24'h370c_03;
236:     LUT_DATA    = 24'h3a02_02; // 60Hz max exposure
237:     LUT_DATA    = 24'h3a03_e0; // 60Hz max exposure
238:     LUT_DATA    = 24'h3a14_02; // 50Hz max exposure
239:     LUT_DATA    = 24'h3a15_e0; // 50Hz max exposure
240:     LUT_DATA    = 24'h4004_02; // BLC line number
241:     LUT_DATA    = 24'h3002_1c; // reset JFIFO, SFIFO, JPG
242:     LUT_DATA    = 24'h3006_c3; // disable clock of JPEG2x, JPEG
243:     LUT_DATA    = 24'h4713_03; // JPEG mode 3
244:     LUT_DATA    = 24'h4407_04; // Quantization scale
245:     LUT_DATA    = 24'h460b_37;
246:     LUT_DATA    = 24'h460c_20;
247:     LUT_DATA    = 24'h4837_16; // MIPI global timing
248:     LUT_DATA    = 24'h3824_04; // PCLK manual divider
249:     LUT_DATA    = 24'h5001_83; // SDE on, CMX on, AWB on
250:     LUT_DATA    = 24'h3503_00; // AEC/AGC on
251:     LUT_DATA    = 24'h4740_21; // VS 1
	default:LUT_DATA	=	{16'h0000, 8'h0000};
	endcase
end

endmodule
