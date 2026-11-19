CLibrary subclass: #UefiBuiltins
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiBuiltins comment: 'The compiler builtins UefiLibM uses: no header, no library; the C compiler expands them inline (sqrt to one instruction: compile with -fno-math-errno, or the compiler calls sqrt for a negative argument to set errno). Simulated: the host''s IEEE square root.'!

!UefiBuiltins class methodsFor: 'declaring'!
targetOS
	^#uefi
! !

!UefiBuiltins methodsFor: 'functions'!
sqrt: x
	<c: 'double __builtin_sqrt(double x)'>
	^x sqrt
! !

VMModule subclass: #UefiLibM
	instanceVariableNames: 'builtins ipio2 pio2Parts atanHi atanLo expTail expBits logInvc logLogc logChi logClo'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiLibM comment: 'The C math library of the VM core (LibM) where there is no libc (UEFI): the same functions with the same C signatures, and formatDouble:precision:conversion:into:size:, one double conversion of printf (%e %f %g).

sin, cos, atan, exp and log are those of musl (MIT): fdlibm''s sin, cos (with __rem_pio2 and __rem_pio2_large for any argument) and atan, ARM''s optimized-routines exp and log (which glibc uses too), without FMA. trunc, fabs, modf, frexp, ilogb and ldexp work on the bits (ldexp is musl''s scalbn); sqrt is the compiler''s builtin (one instruction).

strtod and formatDouble are exact: strtod keeps the first 800 significant digits (and whether any later digit is not zero, which is all the rounding of a double needs), divides the digits times a power of 5 by another with integers of 32-bit limbs and rounds the quotient once, half to even. formatDouble expands the double''s binary value into all its decimal digits and rounds those half to even, as glibc''s printf does. Both answer what glibc answers, byte for byte (strtod: no hexadecimal floats; nan(...) payloads as glibc).

ilogb answers glibc''s values on x86-64 for 0 and NaN (INT_MIN) and infinity (INT_MAX).

sin, cos, their argument reduction and atan are derived from fdlibm: Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved. Developed at SunSoft, a Sun Microsystems, Inc. business. Permission to use, copy, modify, and distribute this software is freely granted, provided that this notice is preserved. exp and log, their tables and scalbn are derived from musl (Copyright (c) 2005-2020 Rich Felker, et al.; MIT license) and Arm''s optimized-routines (Copyright (c) 2018, Arm Limited; SPDX-License-Identifier: MIT).'!

!UefiLibM class methodsFor: 'declaring'!
targetOS
	^#uefi
!
implementsLibrary
	^LibM
!
declarations
	"ipio2: the bits of 2/pi, 24 at a time; pio2Parts: pi/2 in parts of 24 bits; atanHi + atanLo: atan of 0.5, 1, 1.5 and infinity; expTail, expBits: 2^(k/128) is the double with the bits expBits[k] + (k << 45) times 1 + expTail[k] (musl's __exp_data.tab); logInvc, logLogc: 1/c and log(c) of the 128 subintervals of [0.6875, 1.375), logChi + logClo: c (musl's __log_data)."
	^#((builtins UefiBuiltins)
		(ipio2 'int32_t[66]' #(
		16rA2F983 16r6E4E44 16r1529FC 16r2757D1 16rF534DD 16rC0DB62
		16r95993C 16r439041 16rFE5163 16rABDEBB 16rC561B7 16r246E3A
		16r424DD2 16rE00649 16r2EEA09 16rD1921C 16rFE1DEB 16r1CB129
		16rA73EE8 16r8235F5 16r2EBB44 16r84E99C 16r7026B4 16r5F7E41
		16r3991D6 16r398353 16r39F49C 16r845F8B 16rBDF928 16r3B1FF8
		16r97FFDE 16r05980F 16rEF2F11 16r8B5A0A 16r6D1F6D 16r367ECF
		16r27CB09 16rB74F46 16r3F669E 16r5FEA2D 16r7527BA 16rC7EBE5
		16rF17B3D 16r0739F7 16r8A5292 16rEA6BFB 16r5FB11F 16r8D5D08
		16r560330 16r46FC7B 16r6BABF0 16rCFBC20 16r9AF436 16r1DA9E3
		16r91615E 16rE61B08 16r659985 16r5F14A0 16r68408D 16rFFD880
		16r4D7327 16r310606 16r1556CA 16r73A8C9 16r60E27B 16rC08C6B))
		(pio2Parts 'double[8]' #(
		1.570796251296997 7.549789415861596e-8 5.390302529957765e-15 3.282003415807913e-22 1.270655753080676e-29 1.2293330898111133e-36
		2.7337005381646456e-44 2.1674168387780482e-51))
		(atanHi 'double[4]' #(0.4636476090008061 0.7853981633974483 0.982793723247329 1.5707963267948966))
		(atanLo 'double[4]' #(2.2698777452961687e-17 3.061616997868383e-17 1.3903311031230998e-17 6.123233995736766e-17))
		(expTail 'double[128]' #(
		0.0 9.447885451727066e-17 -1.507066976926039e-17 -5.679155082825012e-17
		4.9997448722726326e-17 -4.823683599994895e-17 7.357846871247418e-18 5.773230223741951e-17
		8.189317638195515e-17 5.326891139980878e-17 1.6665881442326747e-18 -1.128113245461828e-17
		-7.402825309426177e-17 -3.578659767309563e-18 -6.170654745608695e-17 2.919139999949279e-17
		-2.7939114859515733e-17 -5.399285355184285e-17 4.776959425256223e-17 -7.927701432338473e-17
		9.341710609905046e-17 -5.534520675707472e-17 4.585670326662351e-17 2.8582430411116143e-17
		7.826573258636076e-17 4.053626906769216e-17 2.823784425951061e-17 -7.882802262487991e-17
		3.2904726646008416e-17 -1.5792094703347882e-18 4.721368121170128e-17 1.3045277096919659e-17
		3.3484623336251524e-17 3.8611199774925664e-17 5.527550048505249e-17 -3.927184172445234e-17
		-6.346552106729483e-17 -8.684417614865944e-17 -1.5456342819397733e-17 -8.70763476495455e-17
		3.750854201303127e-17 -6.616854503526488e-17 -5.346099009198751e-18 -2.443726321015018e-17
		2.1023049675215714e-18 7.771067937501065e-17 1.3357510088834541e-17 6.938291696959204e-17
		1.9572585293112036e-17 6.632256961675804e-17 -5.478069123926778e-17 -4.140839310392624e-17
		-2.1571477251208752e-17 -3.8287766552120535e-17 6.663804589232195e-17 2.3936187400285282e-17
		5.68648095791174e-17 1.1264523354521684e-18 7.007875046906994e-17 -5.0119214278381254e-17
		-4.8923067513522756e-17 -3.5260089953269434e-17 -6.872303720902018e-17 5.001446664133532e-18
		-6.835808657661922e-17 -1.1307344092910212e-17 -8.416011634717156e-18 -2.9247977035436566e-17
		-2.092304381843353e-17 -3.9778645875427124e-17 -3.833464968654295e-17 5.763611164480894e-17
		-2.3591094770850053e-17 7.260074661098575e-17 9.50689710108796e-18 -4.272956133839906e-17
		-6.735219232374683e-17 -2.8396044410430936e-17 -7.226635472101257e-17 5.786121003395918e-17
		5.1548301170786783e-17 -9.416257568878152e-18 2.4253985766689806e-17 -6.604314051707707e-17
		-6.432131775424189e-18 -1.2204007601863921e-17 -6.336161863401293e-17 -3.7800879246373815e-17
		1.5341410053603723e-17 1.2932855580427452e-17 -4.123367330661149e-17 4.703083974463456e-17
		-6.152602891550265e-17 5.827849326195279e-17 3.540948262646183e-17 -3.2741571320938764e-17
		4.875160526227062e-17 -5.718569790077838e-17 -4.719539664590972e-18 -5.773451958805706e-17
		-1.0772487078934056e-17 -6.221808618533911e-17 1.821405440362259e-17 -6.155536546227639e-17
		1.685487290628973e-17 5.3581249177694816e-17 3.621615935336894e-17 8.588379527574144e-18
		1.01562190116415e-17 -2.869134889187244e-17 -5.495118966122005e-17 -5.56965572431627e-17
		1.790126907604513e-17 -3.2211766346200164e-17 5.265370768556274e-17 3.5089866402403033e-17
		-3.266924100901318e-17 -4.3657593008079375e-17 1.7963932659833022e-17 3.4300925275214166e-17
		-5.545065618639427e-17 -5.149009745457733e-17 5.336805878514151e-17 3.498978661192973e-17
		4.5784915277060095e-17 -5.241934575393899e-17 2.0414278897578303e-17 4.124842848606488e-18))
		(expBits 'uint64_t[128]' #(
		16r3FF0000000000000 16r3FEFF63DA9FB3335 16r3FEFEC9A3E778061 16r3FEFE315E86E7F85
		16r3FEFD9B0D3158574 16r3FEFD06B29DDF6DE 16r3FEFC74518759BC8 16r3FEFBE3ECAC6F383
		16r3FEFB5586CF9890F 16r3FEFAC922B7247F7 16r3FEFA3EC32D3D1A2 16r3FEF9B66AFFED31B
		16r3FEF9301D0125B51 16r3FEF8ABDC06C31CC 16r3FEF829AAEA92DE0 16r3FEF7A98C8A58E51
		16r3FEF72B83C7D517B 16r3FEF6AF9388C8DEA 16r3FEF635BEB6FCB75 16r3FEF5BE084045CD4
		16r3FEF54873168B9AA 16r3FEF4D5022FCD91D 16r3FEF463B88628CD6 16r3FEF3F49917DDC96
		16r3FEF387A6E756238 16r3FEF31CE4FB2A63F 16r3FEF2B4565E27CDD 16r3FEF24DFE1F56381
		16r3FEF1E9DF51FDEE1 16r3FEF187FD0DAD990 16r3FEF1285A6E4030B 16r3FEF0CAFA93E2F56
		16r3FEF06FE0A31B715 16r3FEF0170FC4CD831 16r3FEEFC08B26416FF 16r3FEEF6C55F929FF1
		16r3FEEF1A7373AA9CB 16r3FEEECAE6D05D866 16r3FEEE7DB34E59FF7 16r3FEEE32DC313A8E5
		16r3FEEDEA64C123422 16r3FEEDA4504AC801C 16r3FEED60A21F72E2A 16r3FEED1F5D950A897
		16r3FEECE086061892D 16r3FEECA41ED1D0057 16r3FEEC6A2B5C13CD0 16r3FEEC32AF0D7D3DE
		16r3FEEBFDAD5362A27 16r3FEEBCB299FDDD0D 16r3FEEB9B2769D2CA7 16r3FEEB6DAA2CF6642
		16r3FEEB42B569D4F82 16r3FEEB1A4CA5D920F 16r3FEEAF4736B527DA 16r3FEEAD12D497C7FD
		16r3FEEAB07DD485429 16r3FEEA9268A5946B7 16r3FEEA76F15AD2148 16r3FEEA5E1B976DC09
		16r3FEEA47EB03A5585 16r3FEEA34634CCC320 16r3FEEA23882552225 16r3FEEA155D44CA973
		16r3FEEA09E667F3BCD 16r3FEEA012750BDABF 16r3FEE9FB23C651A2F 16r3FEE9F7DF9519484
		16r3FEE9F75E8EC5F74 16r3FEE9F9A48A58174 16r3FEE9FEB564267C9 16r3FEEA0694FDE5D3F
		16r3FEEA11473EB0187 16r3FEEA1ED0130C132 16r3FEEA2F336CF4E62 16r3FEEA427543E1A12
		16r3FEEA589994CCE13 16r3FEEA71A4623C7AD 16r3FEEA8D99B4492ED 16r3FEEAAC7D98A6699
		16r3FEEACE5422AA0DB 16r3FEEAF3216B5448C 16r3FEEB1AE99157736 16r3FEEB45B0B91FFC6
		16r3FEEB737B0CDC5E5 16r3FEEBA44CBC8520F 16r3FEEBD829FDE4E50 16r3FEEC0F170CA07BA
		16r3FEEC49182A3F090 16r3FEEC86319E32323 16r3FEECC667B5DE565 16r3FEED09BEC4A2D33
		16r3FEED503B23E255D 16r3FEED99E1330B358 16r3FEEDE6B5579FDBF 16r3FEEE36BBFD3F37A
		16r3FEEE89F995AD3AD 16r3FEEEE07298DB666 16r3FEEF3A2B84F15FB 16r3FEEF9728DE5593A
		16r3FEEFF76F2FB5E47 16r3FEF05B030A1064A 16r3FEF0C1E904BC1D2 16r3FEF12C25BD71E09
		16r3FEF199BDD85529C 16r3FEF20AB5FFFD07A 16r3FEF27F12E57D14B 16r3FEF2F6D9406E7B5
		16r3FEF3720DCEF9069 16r3FEF3F0B555DC3FA 16r3FEF472D4A07897C 16r3FEF4F87080D89F2
		16r3FEF5818DCFBA487 16r3FEF60E316C98398 16r3FEF69E603DB3285 16r3FEF7321F301B460
		16r3FEF7C97337B9B5F 16r3FEF864614F5A129 16r3FEF902EE78B3FF6 16r3FEF9A51FBC74C83
		16r3FEFA4AFA2A490DA 16r3FEFAF482D8E67F1 16r3FEFBA1BEE615A27 16r3FEFC52B376BBA97
		16r3FEFD0765B6E4540 16r3FEFDBFDAD9CBE14 16r3FEFE7C1819E90D8 16r3FEFF3C22B8F71F1))
		(logInvc 'double[128]' #(
		1.4504249240398293 1.442253508327276 1.4341736174350004 1.426183816329995
		1.4182825527052965 1.4104682921759335 1.4027396147468003 1.3950954438932313
		1.3875338232485754 1.3800539211058593 1.3726542695419708 1.3653332798446802
		1.358090204587874 1.3509234892132138 1.3438320840699889 1.3368146974742003
		1.329870114677736 1.322997339161106 1.316195352741367 1.3094628125672239
		1.3027990455471041 1.2962024229438942 1.2896726275815547 1.2832080305745537
		1.276807885983376 1.2704714060687552 1.2641976054949482 1.257985357514882
		1.2518337750655457 1.2457421919097305 1.2397094966625508 1.2337348463589233
		1.2278176973028803 1.2219570190618474 1.2161519732977757 1.2104018095009725
		1.204705805718973 1.1990631185441964 1.1934733004462308 1.1879350812847385
		1.1824481322833125 1.1770114976921955 1.1716248121809465 1.1662869231674715
		1.1609977486762766 1.1557563220795803 1.1505619105480347 1.1454138888505974
		1.140311877374656 1.1352550225747513 1.1302429094831266 1.1252747693068048
		1.1203501571039876 1.1154683327680124 1.1106291463292157 1.1058315813301596
		1.1010752177696026 1.0963597137952512 1.0916844827550398 1.0870487291277784
		1.082452357388312 1.0778948225025884 1.0733751731601076 1.068893585073351
		1.0644491706655506 1.0600414846328305 1.0556701316181605 1.051334750556926
		1.0470347288442157 1.0427699229652954 1.0385395013738175 1.034343418940345
		1.0301811073173315 1.026052043621297 1.0219561082336197 1.0178926505784922
		1.0138614436244586 1.0098620186501341 1.0058938559734134 1.00195696235014
		0.9961089923088509 0.9884170338185201 0.9808429191005297 0.9733840169987446
		0.9660377568876556 0.9588014945307369 0.9516728569073111 0.9446494635965822
		0.9377288993026223 0.9309091073790681 0.924187681612722 0.9175626765599192
		0.9110320403624034 0.9045935839762024 0.8982456375922825 0.8919860966782501
		0.8858131121185129 0.879725075760676 0.8737201372634685 0.8677966405782273
		0.8619528050060739 0.8561872354420692 0.8504983927816893 0.8448844572790304
		0.8393442741575965 0.8338762249349438 0.8284789320557778 0.8231510800065832
		0.8178913903778707 0.8126984007245374 0.8075710029460227 0.8025078881160415
		0.7975077379364331 0.792569604966373 0.7876923641254114 0.7828746724940998
		0.7781155388790811 0.7734139557869777 0.7687687179914933 0.7641790698041854
		0.7596438763692399 0.7551621951078668 0.7507331780216866 0.7463557196361751
		0.7420289364869653 0.7377521537065876 0.7335242966002608 0.729344777457841))
		(logLogc 'double[128]' #(
		-0.3718565645633589 -0.36620682668944937 -0.3605888069791945 -0.3550022171419869
		-0.34944666968829097 -0.3439217713603284 -0.3384271921261188 -0.332962831494342
		-0.32752794345742586 -0.32212257167088865 -0.3167462884799761 -0.3113985598928366
		-0.3060794515165526 -0.300788424667644 -0.2955252968476998 -0.29028969275850613
		-0.2850812793277555 -0.27989987391470095 -0.27474526621870154 -0.2696169863701243
		-0.26451506180308115 -0.2594387762767383 -0.2543884090981692 -0.24936321635129843
		-0.24436312405975968 -0.23938801747897287 -0.23443761696705678 -0.22951151871518505
		-0.2246094963439873 -0.21973149037705753 -0.2148770752847895 -0.210046029103637
		-0.20523836373934046 -0.20045368751368642 -0.1956917537758045 -0.19095237845203883
		-0.18623539250290833 -0.18154051731551135 -0.1768677957431919 -0.17221657406412305
		-0.16758697765942543 -0.16297859687290384 -0.15839151377804228 -0.15382513241456763
		-0.14927976358922024 -0.14475495398119165 -0.14025044090817573 -0.1357660466685502
		-0.1313018016355727 -0.12685731518763532 -0.1224325737671279 -0.11802724521862729
		-0.11364127671663482 -0.10927434611278386 -0.10492665324943573 -0.10059761422644442
		-0.09628717309055901 -0.09199534069557558 -0.08772190036688698 -0.08346643613867855
		-0.07922916827544668 -0.0750099004750382 -0.07080805133352897 -0.06662408085151128
		-0.06245745471915143 -0.0583080438042316 -0.05417576112313327 -0.050060547896805474
		-0.045962101199052086 -0.04188056008865715 -0.03781540056183985 -0.03376684757915882
		-0.029734619131772888 -0.025718470239212365 -0.021718543925430822 -0.01773446126981071
		-0.013766252464051831 -0.009813706322574944 -0.005876555150052809 -0.0019550499938532084
		0.0038985973556009412 0.011650571286395461 0.019342955478919066 0.0269766014846482
		0.034552359728422744 0.04207121767183253 0.049533940950141186 0.056941358295944156
		0.06429439168346107 0.0715936354946507 0.07884010933776153 0.08603438905970506
		0.09317721180013905 0.10026951462748457 0.10731170956330516 0.11430473320717738
		0.12124928503033061 0.12814583422959913 0.1349951636851756 0.1417978768189414
		0.14855476039031146 0.1552661937658968 0.16193275688146969 0.16855539792220497
		0.1751343179947753 0.1816702989864325 0.18816387146023317 0.1946155228479256
		0.20102572579389744 0.2073952090795501 0.21372429840596396 0.2200135945981856
		0.22626374162859975 0.23247494747693054 0.23864766620658884 0.24478265647405806
		0.25088025827324145 0.2569408552510595 0.26296511155101143 0.2689531327189343
		0.27490553924610595 0.2808227248478943 0.286704979267256 0.29255295645509705
		0.2983670386142876 0.30414734587282055 0.30989455774829366 0.31560871301871884))
		(logChi 'double[128]' #(
		0.6894531274426304 0.6933593811533166 0.6972656502972674 0.7011718886092148
		0.7050781228976939 0.7089843887644558 0.7128906815542553 0.7167968359278303
		0.7207031520563163 0.7246093683054673 0.7285155644718035 0.7324219036935506
		0.73632811474659 0.7402343715130797 0.7441405900738403 0.7480468324364
		0.7519531335902885 0.7558594189116706 0.7597656365502305 0.7636719350887737
		0.767578087670501 0.7714844396979536 0.7753905747966752 0.7792968686084766
		0.783203182701066 0.7871094109030913 0.7910155783031153 0.7949218121071572
		0.7988281031542229 0.8027343109146796 0.8066405901480322 0.8105469363625933
		0.8144531571720115 0.8183593894061396 0.8222656559018297 0.8261719308006343
		0.830078177803083 0.8339844538076674 0.8378905498984414 0.8417968420618669
		0.8457030568173808 0.8496093725173733 0.8535155534462677 0.8574219432077146
		0.8613281129443706 0.8652342893532053 0.8691405397938828 0.8730468608194392
		0.8769530685783117 0.8808593488818101 0.8847655593409667 0.888671840226208
		0.8925780870017613 0.8964844367374554 0.9003905608862683 0.9042968358682077
		0.9082031671057441 0.9121093993305497 0.9160155849026457 0.9199219622862499
		0.9238281880717143 0.9277343012727929 0.9316407021562788 0.935546825207466
		0.9394530312562943 0.9433593066844669 0.9472655994038329 0.9511718313032721
		0.9550781578218178 0.9589843147339043 0.9628906735633685 0.9667968893972092
		0.9707031054025779 0.9746094325494931 0.9785156054582722 0.9824218687812282
		0.9863280690752917 0.9902342909546034 0.9941406780264008 0.9980468598715558
		1.0039062067717412 1.0117187035281372 1.0195312424919558 1.0273437641634193
		1.0351562274561221 1.0429687539123276 1.0507812561238108 1.0585937308350133
		1.0664062936992642 1.0742187309945372 1.082031301537134 1.0898438063644336
		1.0976562356711468 1.1054688179463226 1.113281220803328 1.1210937073167315
		1.1289062967338532 1.1367187631150848 1.1445312490244826 1.1523437096203593
		1.1601563266482477 1.1679688257483505 1.1757811754697645 1.183593793665613
		1.1914062331617676 1.1992187450577771 1.2070312971249755 1.2148438169965134
		1.222656225220801 1.2304687681290862 1.2382812116234925 1.2460936706149877
		1.2539063289686938 1.2617188367227732 1.2695311590462317 1.277343660657941
		1.2851561882963496 1.2929686521915196 1.3007813359167737 1.3085938093753886
		1.3164063202609564 1.3242188320313901 1.3320311786874468 1.3398436880573092
		1.3476563390295309 1.3554687641043626 1.3632813590971713 1.3710936595522603))
		(logClo 'double[128]' #(
		2.60290652810535e-17 5.1607448519931415e-17 5.290672414887869e-17 7.801030634806013e-18
		-2.471355337688684e-17 -4.6413389636862956e-17 3.3387408065940366e-17 -2.6454587338050098e-17
		2.4284096334522285e-17 4.85782435031982e-17 -1.3014776598894487e-17 -1.0402317671225898e-17
		3.078291427467431e-17 -1.4304998976623033e-17 -2.8625955785571303e-17 5.1609093535635645e-17
		4.423423949536319e-17 -4.683016762099508e-17 4.466742007514772e-17 -4.8134498775190266e-17
		-4.3371015350542286e-17 -2.515644472251707e-17 -4.163636184961329e-17 3.3837161384165165e-17
		4.379206565056758e-17 2.7322930976146396e-17 -5.463661225364046e-17 -1.4320502634189868e-17
		-4.0766731402809024e-17 -4.0338264352540086e-17 1.7241428071650815e-18 -4.5534218930924523e-17
		1.821216920589142e-17 4.9864288025894273e-17 4.335990416726689e-17 -5.422001471661127e-17
		-5.333603728929035e-17 -1.1270648442682386e-17 -3.165126734800398e-17 1.1286283062565865e-17
		5.643595964448442e-18 -2.1687834632368187e-17 -2.2548234217914977e-17 4.683260556353139e-17
		2.5148296884122795e-17 -8.672187570949467e-18 -1.2576268285559751e-17 -2.9930851265148e-17
		4.814801507681644e-17 -9.10549533611022e-18 -3.512414651620766e-17 3.555261815374023e-17
		1.692380503540994e-17 -1.0837881791715702e-17 5.2900545724138363e-17 5.3330721088784517e-17
		1.8640040753232978e-17 4.467972832054075e-17 -5.216213419585033e-18 -2.7324731032846873e-17
		-1.7769263393434193e-17 4.943363080817441e-17 4.164434042024055e-17 1.3011820859795741e-17
		-2.7332907838481398e-17 2.342133170803292e-17 1.6478717480487438e-17 -5.19608290131499e-18
		-3.5565573220579e-17 2.0816772146458738e-17 -3.471962826146841e-18 -3.68646834472642e-17
		-3.4674108076868834e-18 4.598152624774392e-17 4.553145752392568e-17 -7.811259169418978e-18
		2.0375615178047467e-17 -1.344597043422914e-17 1.51853723695054e-17 -1.301926039598001e-17
		-4.596120641744973e-17 -8.152405002665349e-17 8.239927014757811e-17 3.122851005327045e-17
		-1.3010212611128995e-17 -5.984116688633458e-17 2.860923854822335e-17 -1.9962944508904598e-17
		5.291469130309099e-17 1.0321575006732523e-16 9.021194373419119e-17 5.202798992357953e-17
		5.898318482500785e-17 8.846377690653252e-17 -9.529455965212574e-18 6.765080709377787e-17
		1.0929327370933015e-16 6.938570551230516e-17 1.908841015045148e-17 2.7744504138979832e-17
		-1.5621964097491672e-17 -6.4191661495975e-17 -4.336465165059268e-17 -3.8159292551356396e-17
		-2.94933042768015e-17 -6.244142916351348e-17 7.458644622627413e-17 2.7760519266147807e-17
		-7.025106921079665e-17 3.7292622364618835e-17 2.2558949940652082e-17 8.499368944400665e-17
		1.039515474644361e-17 3.297262223275499e-17 4.509883253594155e-17 -7.546987371769545e-17
		9.454295598818184e-17 -7.28545609119749e-17 -8.934357651462802e-17 8.15257059458102e-17
		6.946341460765881e-18 -7.892731380721676e-17 -4.3384657500713545e-17 9.627577954598792e-17
		4.2492400590204517e-17 -1.0843419551446047e-16 -8.50172782472025e-17 -7.110627206162922e-17)))
! !

!UefiLibM methodsFor: 'bits'!
fabs: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^self doubleFromBits: ((self bitsOfDouble: x) bitAnd: 16r7FFFFFFFFFFFFFFF)
!
trunc: x
	"musl's trunc: clear the fraction bits (never __builtin_trunc: on x86-64 without SSE4.1 it calls trunc)."
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	| u e m |
	u := self bitsOfDouble: x.
	e := ((u >> 52) bitAnd: 16r7FF) asInt64 - 16r3FF + 12.
	e >= (52 + 12) ifTrue: [
		"no fraction; infinity or NaN: x + x (quiet), as glibc"
		^e = (16r400 + 12) ifTrue: [x + x] ifFalse: [x]].
	e < 12 ifTrue: [e := 1].
	m := 16rFFFFFFFFFFFFFFFF asUInt64 >> e.
	(u bitAnd: m) = 0 ifTrue: [^x].
	^self doubleFromBits: (u bitAnd: m bitInvert64)
!
modf: x integralPart: ip
	<function>
	<var: #x type: 'double'>
	<var: #ip type: 'double *'>
	<returns: 'double'>
	| u e mask |
	u := self bitsOfDouble: x.
	e := ((u >> 52) bitAnd: 16r7FF) asInt64 - 16r3FF.
	e >= 52 ifTrue: [
		"no fraction: infinity, NaN (quiet, as glibc) or a large integer"
		(e = 16r400 and: [(u bitAnd: 16rFFFFFFFFFFFFF) ~= 0]) ifTrue: [
			ip value: x + x.
			^x + x].
		ip value: x.
		^self doubleFromBits: (u bitAnd: 16r8000000000000000)].
	e < 0 ifTrue: [
		ip value: (self doubleFromBits: (u bitAnd: 16r8000000000000000)).
		^x].
	mask := 16rFFFFFFFFFFFFF asUInt64 >> e.
	(u bitAnd: mask) = 0 ifTrue: [
		ip value: x.
		^self doubleFromBits: (u bitAnd: 16r8000000000000000)].
	ip value: (self doubleFromBits: (u bitAnd: mask bitInvert64)).
	^x - (self doubleFromBits: (u bitAnd: mask bitInvert64))
!
frexp: x exponent: e
	"glibc's: 0, infinity and NaN answer x + x and the exponent 0."
	<function>
	<var: #x type: 'double'>
	<var: #e type: 'int *'>
	<returns: 'double'>
	| u ee |
	u := self bitsOfDouble: x.
	ee := ((u >> 52) bitAnd: 16r7FF) asInt32.
	(ee = 16r7FF or: [(u bitAnd: 16r7FFFFFFFFFFFFFFF) = 0]) ifTrue: [
		e value: 0.
		^x + x].
	ee = 0 ifTrue: [
		"subnormal: scale by 2^64 first"
		u := self bitsOfDouble: x * 1.8446744073709552e19.
		ee := ((u >> 52) bitAnd: 16r7FF) asInt32 - 64].
	e value: ee - 16r3FE.
	^self doubleFromBits: ((u bitAnd: 16r800FFFFFFFFFFFFF) bitOr: 16r3FE0000000000000)
!
ilogb: x
	"The unbiased exponent; INT_MIN for 0 and NaN, INT_MAX for infinity (glibc on x86-64)."
	<function>
	<var: #x type: 'double'>
	<returns: 'int'>
	| u e m |
	u := self bitsOfDouble: x.
	e := ((u >> 52) bitAnd: 16r7FF) asInt32.
	e = 0 ifTrue: [
		m := (u << 12) asUInt64.
		m = 0 ifTrue: [^-16r80000000].
		e := -16r3FF.
		[(m >> 63) = 0] whileTrue: [
			e := e - 1.
			m := (m << 1) asUInt64].
		^e].
	e = 16r7FF ifTrue: [^(u << 12) asUInt64 = 0 ifTrue: [16r7FFFFFFF] ifFalse: [-16r80000000]].
	^e - 16r3FF
!
ldexp: x exponent: n
	"musl's scalbn: x * 2^n with one rounding (subnormal results too)."
	<function>
	<var: #x type: 'double'>
	<var: #n type: 'int'>
	<returns: 'double'>
	| y k |
	y := x.
	k := n.
	k > 1023
		ifTrue: [
			y := y * 8.98846567431158e307.
			k := k - 1023.
			k > 1023 ifTrue: [
				y := y * 8.98846567431158e307.
				k := k - 1023.
				k > 1023 ifTrue: [k := 1023]]]
		ifFalse: [
			k < -1022 ifTrue: [
				"2^-1022 * 2^53: the final factor is below 2^-53, so the subnormal result is rounded once"
				y := y * 2.004168360008973e-292.
				k := k + (1022 - 53).
				k < -1022 ifTrue: [
					y := y * 2.004168360008973e-292.
					k := k + (1022 - 53).
					k < -1022 ifTrue: [k := -1022]]]].
	^y * (self doubleFromBits: (16r3FF + k) asUInt64 << 52)
!
sqrt: x
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	^builtins sqrt: x
!
infinity
	^self doubleFromBits: 16r7FF0000000000000
!
invalid: x
	"NaN for an argument outside the domain: x itself if it is a NaN, else the CPU's default NaN (computed at run time, as the C library does)."
	| t |
	t := x - x + self infinity.
	^t - t
! !

!UefiLibM methodsFor: 'trigonometry'!
sin: x
	"fdlibm's sin (musl)."
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	| ix y n |
	ix := ((self bitsOfDouble: x) >> 32) asUInt32 bitAnd: 16r7FFFFFFF.
	ix <= 16r3FE921FB ifTrue: [
		"|x| ~< pi/4"
		ix < 16r3E500000 ifTrue: [^x].
		^self kernelSin: x tail: 0.0 tailIsZero: true].
	ix >= 16r7FF00000 ifTrue: [^x - x].
	y := self local: 'double[2]'.
	n := (self remPio2: x into: y) bitAnd: 3.
	n = 0 ifTrue: [^self kernelSin: (y at: 0) tail: (y at: 1) tailIsZero: false].
	n = 1 ifTrue: [^self kernelCos: (y at: 0) tail: (y at: 1)].
	n = 2 ifTrue: [^(self kernelSin: (y at: 0) tail: (y at: 1) tailIsZero: false) negated].
	^(self kernelCos: (y at: 0) tail: (y at: 1)) negated
!
cos: x
	"fdlibm's cos (musl)."
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	| ix y n |
	ix := ((self bitsOfDouble: x) >> 32) asUInt32 bitAnd: 16r7FFFFFFF.
	ix <= 16r3FE921FB ifTrue: [
		ix < 16r3E46A09E ifTrue: [^1.0].
		^self kernelCos: x tail: 0.0].
	ix >= 16r7FF00000 ifTrue: [^x - x].
	y := self local: 'double[2]'.
	n := (self remPio2: x into: y) bitAnd: 3.
	n = 0 ifTrue: [^self kernelCos: (y at: 0) tail: (y at: 1)].
	n = 1 ifTrue: [^(self kernelSin: (y at: 0) tail: (y at: 1) tailIsZero: false) negated].
	n = 2 ifTrue: [^(self kernelCos: (y at: 0) tail: (y at: 1)) negated].
	^self kernelSin: (y at: 0) tail: (y at: 1) tailIsZero: false
!
kernelSin: x tail: y tailIsZero: iy
	"__sin: sin(x + y) on [-pi/4, pi/4], y the tail of x."
	<function>
	<var: #x type: 'double'>
	<var: #y type: 'double'>
	<var: #iy type: 'bool'>
	<returns: 'double'>
	| z w r v |
	z := x * x.
	w := z * z.
	r := 0.00833333333332249 + (z * (-0.0001984126982985795 + (z * 2.7557313707070068e-6))) + (z * w * (-2.5050760253406863e-8 + (z * 1.58969099521155e-10))).
	v := z * x.
	iy ifTrue: [^x + (v * (-0.16666666666666632 + (z * r)))].
	^x - ((z * ((0.5 * y) - (v * r))) - y - (v * -0.16666666666666632))
!
kernelCos: x tail: y
	"__cos: cos(x + y) on [-pi/4, pi/4], y the tail of x."
	<function>
	<var: #x type: 'double'>
	<var: #y type: 'double'>
	<returns: 'double'>
	| z w r hz |
	z := x * x.
	w := z * z.
	r := (z * (0.0416666666666666 + (z * (-0.001388888888887411 + (z * 2.480158728947673e-5))))) + (w * w * (-2.7557314351390663e-7 + (z * (2.087572321298175e-9 + (z * -1.1359647557788195e-11))))).
	hz := 0.5 * z.
	w := 1.0 - hz.
	^w + (1.0 - w - hz + ((z * r) - (x * y)))
!
remPio2: x into: y
	"__rem_pio2: answer n and y[0] + y[1] = x - n * pi/2, |y[0]| ~<= pi/4, for |x| ~> pi/4 (finite or not)."
	<function>
	<var: #x type: 'double'>
	<var: #y type: 'double *'>
	<var: #count type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<var: #nx type: 'int32_t'>
	<returns: 'int32_t'>
	| u sign ix count m z fn n r w t y0 ex ey tx ty nx |
	u := self bitsOfDouble: x.
	sign := (u >> 63) ~= 0.
	ix := ((u >> 32) bitAnd: 16r7FFFFFFF) asUInt32.
	((ix <= 16r400F6A7A and: [(ix bitAnd: 16rFFFFF) ~= 16r921FB])
		or: [ix > 16r400F6A7A and: [ix <= 16r401C463B and: [ix ~= 16r4012D97C and: [ix ~= 16r401921FB]]]]) ifTrue: [
		"|x| ~<= 9pi/4 and not close to a multiple of pi/2: n is 1 to 4, one subtraction of pio2_1 good to 85 bits"
		count := ix <= 16r4002D97C ifTrue: [1] ifFalse: [ix <= 16r400F6A7A ifTrue: [2] ifFalse: [ix <= 16r4015FDBC ifTrue: [3] ifFalse: [4]]].
		m := count asFloat.
		sign ifTrue: [
			z := x + (m * 1.5707963267341256).
			y at: 0 put: z + (m * 6.077100506506192e-11).
			y at: 1 put: z - (y at: 0) + (m * 6.077100506506192e-11).
			^count negated].
		z := x - (m * 1.5707963267341256).
		y at: 0 put: z - (m * 6.077100506506192e-11).
		y at: 1 put: z - (y at: 0) - (m * 6.077100506506192e-11).
		^count].
	ix < 16r413921FB ifTrue: [
		"|x| ~< 2^20 * pi/2: n is x * 2/pi rounded, then up to three rounds of pi/2 in 33-bit parts"
		fn := x * 0.6366197723675814 + 6755399441055744.0 - 6755399441055744.0.
		n := fn truncated asInt32.
		r := x - (fn * 1.5707963267341256).
		w := fn * 6.077100506506192e-11.
		r - w < -0.7853981633974483
			ifTrue: [
				n := n - 1.
				fn := fn - 1.0.
				r := x - (fn * 1.5707963267341256).
				w := fn * 6.077100506506192e-11]
			ifFalse: [
				r - w > 0.7853981633974483 ifTrue: [
					n := n + 1.
					fn := fn + 1.0.
					r := x - (fn * 1.5707963267341256).
					w := fn * 6.077100506506192e-11]].
		y0 := r - w.
		ex := (ix >> 20) asInt32.
		ey := ((self bitsOfDouble: y0) >> 52 bitAnd: 16r7FF) asInt32.
		ex - ey > 16 ifTrue: [
			t := r.
			w := fn * 6.077100506303966e-11.
			r := t - w.
			w := (fn * 2.0222662487959506e-21) - (t - r - w).
			y0 := r - w.
			ey := ((self bitsOfDouble: y0) >> 52 bitAnd: 16r7FF) asInt32.
			ex - ey > 49 ifTrue: [
				t := r.
				w := fn * 2.0222662487111665e-21.
				r := t - w.
				w := (fn * 8.4784276603689e-32) - (t - r - w).
				y0 := r - w]].
		y at: 0 put: y0.
		y at: 1 put: r - y0 - w.
		^n].
	ix >= 16r7FF00000 ifTrue: [
		"infinity or NaN"
		y at: 0 put: x - x.
		y at: 1 put: x - x.
		^0].
	"large: |x| as three 24-bit parts times 2^e0"
	z := self doubleFromBits: ((u bitAnd: 16rFFFFFFFFFFFFF) bitOr: (16r3FF + 23) asUInt64 << 52).
	tx := self local: 'double[3]'.
	tx at: 0 put: z truncated asFloat.
	z := z - (tx at: 0) * 16777216.0.
	tx at: 1 put: z truncated asFloat.
	z := z - (tx at: 1) * 16777216.0.
	tx at: 2 put: z.
	nx := 3.
	[(tx at: nx - 1) = 0.0] whileTrue: [nx := nx - 1].
	ty := self local: 'double[2]'.
	n := self remPio2Large: tx count: nx exponent: (ix >> 20) asInt32 - (16r3FF + 23) into: ty.
	sign ifTrue: [
		y at: 0 put: (ty at: 0) negated.
		y at: 1 put: (ty at: 1) negated.
		^n negated].
	y at: 0 put: (ty at: 0).
	y at: 1 put: (ty at: 1).
	^n
!
remPio2Large: x count: nx exponent: e0 into: y
	"__rem_pio2_large for doubles (prec 1): x[0..nx-1] are 24-bit parts of the argument, x[i] * 2^(e0 - 24i); answer n mod 8 and y[0] + y[1] = the argument - n * pi/2, from enough bits of 2/pi (ipio2)."
	<function>
	<var: #x type: 'double *'>
	<var: #nx type: 'int32_t'>
	<var: #e0 type: 'int32_t'>
	<var: #y type: 'double *'>
	<var: #jz type: 'int32_t'>
	<var: #j type: 'int32_t'>
	<var: #k type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<var: #ih type: 'int32_t'>
	<returns: 'int32_t'>
	| jk jp jx jv q0 f q fq iq jz z fw n ih carry j k bits again |
	jk := 4.
	jp := 4.
	jx := nx - 1.
	jv := (e0 - 3) quo: 24.
	jv < 0 ifTrue: [jv := 0].
	q0 := e0 - (24 * (jv + 1)).
	f := self local: 'double[20]'.
	q := self local: 'double[20]'.
	fq := self local: 'double[20]'.
	iq := self local: 'int32_t[20]'.
	"f[0 .. jx + jk] := ipio2[jv - jx .. jv + jk]"
	j := jv - jx.
	0 to: jx + jk do: [:i |
		f at: i put: (j < 0 ifTrue: [0.0] ifFalse: [(ipio2 at: j) asFloat]).
		j := j + 1].
	0 to: jk do: [:i |
		fw := 0.0.
		0 to: jx do: [:jj | fw := fw + ((x at: jj) * (f at: jx + i - jj))].
		q at: i put: fw].
	jz := jk.
	again := true.
	[again] whileTrue: [
		again := false.
		"distill q[] into iq[] reversingly"
		z := q at: jz.
		j := jz.
		0 to: jz - 1 do: [:i |
			fw := (5.960464477539063e-8 * z) truncated asFloat.
			iq at: i put: (z - (16777216.0 * fw)) truncated asInt32.
			z := (q at: j - 1) + fw.
			j := j - 1].
		"n := the integer part of z mod 8"
		z := self ldexp: z exponent: q0.
		z := z - (8.0 * (z * 0.125) truncated asFloat).
		n := z truncated asInt32.
		z := z - n asFloat.
		ih := 0.
		q0 > 0
			ifTrue: [
				"iq[jz-1] holds bits of n"
				bits := (iq at: jz - 1) >> (24 - q0).
				n := n + bits.
				iq at: jz - 1 put: (iq at: jz - 1) - (bits asInt64 << (24 - q0)).
				ih := (iq at: jz - 1) >> (23 - q0)]
			ifFalse: [
				q0 = 0
					ifTrue: [ih := (iq at: jz - 1) >> 23]
					ifFalse: [z >= 0.5 ifTrue: [ih := 2]]].
		ih > 0 ifTrue: [
			"q > 0.5: n + 1 and 1 - q"
			n := n + 1.
			carry := 0.
			0 to: jz - 1 do: [:i |
				k := iq at: i.
				carry = 0
					ifTrue: [
						k ~= 0 ifTrue: [
							carry := 1.
							iq at: i put: 16r1000000 - k]]
					ifFalse: [iq at: i put: 16rFFFFFF - k]].
			q0 = 1 ifTrue: [iq at: jz - 1 put: ((iq at: jz - 1) bitAnd: 16r7FFFFF)].
			q0 = 2 ifTrue: [iq at: jz - 1 put: ((iq at: jz - 1) bitAnd: 16r3FFFFF)].
			ih = 2 ifTrue: [
				z := 1.0 - z.
				carry ~= 0 ifTrue: [z := z - (self ldexp: 1.0 exponent: q0)]]].
		"recompute with more terms if the fraction so far is all zero"
		z = 0.0 ifTrue: [
			j := 0.
			jz - 1 to: jk by: -1 do: [:i | j := j bitOr: (iq at: i)].
			j = 0 ifTrue: [
				k := 1.
				[(iq at: jk - k) = 0] whileTrue: [k := k + 1].
				jz + 1 to: jz + k do: [:i |
					f at: jx + i put: (ipio2 at: jv + i) asFloat.
					fw := 0.0.
					0 to: jx do: [:jj | fw := fw + ((x at: jj) * (f at: jx + i - jj))].
					q at: i put: fw].
				jz := jz + k.
				again := true]]].
	"chop off zero terms"
	z = 0.0
		ifTrue: [
			jz := jz - 1.
			q0 := q0 - 24.
			[(iq at: jz) = 0] whileTrue: [
				jz := jz - 1.
				q0 := q0 - 24]]
		ifFalse: [
			"break z into 24-bit parts if necessary"
			z := self ldexp: z exponent: q0 negated.
			z >= 16777216.0
				ifTrue: [
					fw := (5.960464477539063e-8 * z) truncated asFloat.
					iq at: jz put: (z - (16777216.0 * fw)) truncated asInt32.
					jz := jz + 1.
					q0 := q0 + 24.
					iq at: jz put: fw truncated asInt32]
				ifFalse: [iq at: jz put: z truncated asInt32]].
	"the 24-bit parts as doubles"
	fw := self ldexp: 1.0 exponent: q0.
	jz to: 0 by: -1 do: [:i |
		q at: i put: fw * (iq at: i) asFloat.
		fw := fw * 5.960464477539063e-8].
	"times pi/2"
	jz to: 0 by: -1 do: [:i |
		fw := 0.0.
		k := 0.
		[k <= jp and: [k <= (jz - i)]] whileTrue: [
			fw := fw + ((pio2Parts at: k) * (q at: i + k)).
			k := k + 1].
		fq at: jz - i put: fw].
	"compress fq[] into y[]"
	fw := 0.0.
	jz to: 0 by: -1 do: [:i | fw := fw + (fq at: i)].
	y at: 0 put: (ih = 0 ifTrue: [fw] ifFalse: [fw negated]).
	fw := (fq at: 0) - fw.
	1 to: jz do: [:i | fw := fw + (fq at: i)].
	y at: 1 put: (ih = 0 ifTrue: [fw] ifFalse: [fw negated]).
	^n bitAnd: 7
!
atan: x
	"fdlibm's atan (musl)."
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	| u ix sign id ax z w s1 s2 |
	u := self bitsOfDouble: x.
	ix := (u >> 32) asUInt32.
	sign := (ix >> 31) ~= 0.
	ix := ix bitAnd: 16r7FFFFFFF.
	ix >= 16r44100000 ifTrue: [
		"|x| >= 2^66"
		(u bitAnd: 16r7FFFFFFFFFFFFFFF) > 16r7FF0000000000000 ifTrue: [^x + x].
		^sign ifTrue: [-1.5707963267948966] ifFalse: [1.5707963267948966]].
	ix < 16r3FDC0000
		ifTrue: [
			"|x| < 0.4375"
			ix < 16r3E400000 ifTrue: [^x].
			id := -1.
			ax := x]
		ifFalse: [
			ax := self fabs: x.
			ix < 16r3FF30000
				ifTrue: [
					ix < 16r3FE60000
						ifTrue: [
							"7/16 <= |x| < 11/16"
							id := 0.
							ax := (2.0 * ax - 1.0) / (2.0 + ax)]
						ifFalse: [
							"11/16 <= |x| < 19/16"
							id := 1.
							ax := (ax - 1.0) / (ax + 1.0)]]
				ifFalse: [
					ix < 16r40038000
						ifTrue: [
							"19/16 <= |x| < 39/16"
							id := 2.
							ax := (ax - 1.5) / (1.0 + (1.5 * ax))]
						ifFalse: [
							"39/16 <= |x| < 2^66"
							id := 3.
							ax := -1.0 / ax]]].
	z := ax * ax.
	w := z * z.
	s1 := z * (0.3333333333333293 + (w * (0.14285714272503466 + (w * (0.09090887133436507 + (w * (0.06661073137387531 + (w * (0.049768779946159324 + (w * 0.016285820115365782)))))))))).
	s2 := w * (-0.19999999999876483 + (w * (-0.11111110405462356 + (w * (-0.0769187620504483 + (w * (-0.058335701337905735 + (w * -0.036531572744216916)))))))).
	id < 0 ifTrue: [^ax - (ax * (s1 + s2))].
	z := (atanHi at: id) - ((ax * (s1 + s2)) - (atanLo at: id) - ax).
	^sign ifTrue: [z negated] ifFalse: [z]
! !

!UefiLibM methodsFor: 'exponential'!
exp: x
	"ARM's optimized-routines exp (musl, glibc): x = k ln2/128 + r, exp(x) = 2^(k/128) exp(r) from a table and a polynomial."
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	| abstop z kd ki r idx top tail sbits r2 tmp scale |
	abstop := ((self bitsOfDouble: x) >> 52) asUInt32 bitAnd: 16r7FF.
	(abstop - 16r3C9) asUInt32 >= (16r408 - 16r3C9) ifTrue: [
		"|x| < 2^-54: 1 + x"
		abstop < 16r3C9 ifTrue: [^1.0 + x].
		abstop >= 16r409 ifTrue: [
			(self bitsOfDouble: x) = 16rFFF0000000000000 ifTrue: [^0.0].
			abstop >= 16r7FF ifTrue: [^1.0 + x].
			^(self bitsOfDouble: x) >> 63 ~= 0 ifTrue: [0.0] ifFalse: [self infinity]].
		"512 <= |x| < 1024: the result may overflow or underflow"
		abstop := 0].
	z := 184.6649652337873 * x.
	kd := z + 6755399441055744.0.
	ki := self bitsOfDouble: kd.
	kd := kd - 6755399441055744.0.
	r := x + (kd * -0.005415212348111709) + (kd * -1.2864023111638346e-14).
	idx := (ki bitAnd: 127) asInt64.
	top := (ki << 45) asUInt64.
	tail := expTail at: idx.
	sbits := ((expBits at: idx) + top) asUInt64.
	r2 := r * r.
	tmp := tail + r + (r2 * (0.49999999999996786 + (r * 0.16666666666665886))) + (r2 * r2 * (0.0416666808410674 + (r * 0.008333335853059549))).
	abstop = 0 ifTrue: [^self expSpecial: tmp bits: sbits k: ki].
	scale := self doubleFromBits: sbits.
	^scale + (scale * tmp)
!
expSpecial: tmp bits: sbits k: ki
	"scale * (1 + tmp) where the exponent of scale (sbits) may have overflowed: k > 0 may overflow, k < 0 needs care in the subnormal range."
	<function>
	<var: #tmp type: 'double'>
	<var: #sbits type: 'uint64_t'>
	<var: #ki type: 'uint64_t'>
	<returns: 'double'>
	| scale y hi lo |
	(ki bitAnd: 16r80000000) = 0 ifTrue: [
		scale := self doubleFromBits: (sbits - (1009 asUInt64 << 52)) asUInt64.
		^5.486124068793689e303 * (scale + (scale * tmp))].
	scale := self doubleFromBits: (sbits + (1022 asUInt64 << 52)) asUInt64.
	y := scale + (scale * tmp).
	y < 1.0 ifTrue: [
		"round y to the right precision before scaling it into the subnormal range (no double rounding)"
		lo := scale - y + (scale * tmp).
		hi := 1.0 + y.
		lo := 1.0 - hi + y + lo.
		y := hi + lo - 1.0.
		y = 0.0 ifTrue: [y := 0.0]].
	^2.2250738585072014e-308 * y
!
log: x
	"ARM's optimized-routines log (musl, glibc, without FMA): x = 2^k z, log(x) = k ln2 + log(c) + log1p(z/c - 1) with c from a table."
	<function>
	<var: #x type: 'double'>
	<returns: 'double'>
	| ix top r r2 r3 y w rhi rlo hi lo tmp i k iz invc logc z kd |
	ix := self bitsOfDouble: x.
	top := (ix >> 48) asUInt32.
	(ix - 16r3FEE000000000000) asUInt64 < (16r3FF1090000000000 - 16r3FEE000000000000) ifTrue: [
		"x close to 1"
		ix = 16r3FF0000000000000 ifTrue: [^0.0].
		r := x - 1.0.
		r2 := r * r.
		r3 := r * r2.
		y := r3 * (0.3333333333333352 + (r * -0.24999999999998432) + (r2 * 0.19999999999320328)
			+ (r3 * (-0.16666666669929706 + (r * 0.14285715076560868) + (r2 * -0.12499997863982555)
				+ (r3 * (0.11110712032936046 + (r * -0.10000486757818193) + (r2 * 0.09181994006195467) + (r3 * -0.08328363062289341)))))).
		w := r * 134217728.0.
		rhi := r + w - w.
		rlo := r - rhi.
		w := rhi * rhi * -0.5.
		hi := r + w.
		lo := r - hi + w.
		lo := lo + (-0.5 * rlo * (rhi + r)).
		y := y + lo.
		^y + hi].
	(top - 16r10) asUInt32 >= (16r7FF0 - 16r10) ifTrue: [
		"x < 2^-1022, infinity or NaN"
		(ix << 1) asUInt64 = 0 ifTrue: [^self doubleFromBits: 16rFFF0000000000000].
		ix = 16r7FF0000000000000 ifTrue: [^x].
		((top bitAnd: 16r8000) ~= 0 or: [(top bitAnd: 16r7FF0) = 16r7FF0]) ifTrue: [^self invalid: x].
		"subnormal: normalize"
		ix := self bitsOfDouble: x * 4503599627370496.0.
		ix := (ix - (52 asUInt64 << 52)) asUInt64].
	tmp := (ix - 16r3FE6000000000000) asUInt64.
	i := (tmp >> 45 bitAnd: 127) asInt64.
	k := tmp asInt64 >> 52.
	iz := (ix - (tmp bitAnd: 16rFFF0000000000000)) asUInt64.
	invc := logInvc at: i.
	logc := logLogc at: i.
	z := self doubleFromBits: iz.
	r := (z - (logChi at: i) - (logClo at: i)) * invc.
	kd := k asFloat.
	w := (kd * 0.6931471805598903) + logc.
	hi := w + r.
	lo := w - hi + r + (kd * 5.497923018708371e-14).
	r2 := r * r.
	y := lo + (r2 * -0.5000000000000001) + (r * r2 * (0.33333333331825593 + (r * -0.2499999999622955) + (r2 * (0.20000304511814496 + (r * -0.16667054827627667))))) + hi.
	^y
! !

!UefiLibM methodsFor: 'big integers'!
bigMul: a size: n by: m add: c
	"a (n limbs of 32 bits, least significant first) := a * m + c; answer its size (the buffer has room for one more limb)."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<var: #m type: 'uint32_t'>
	<var: #c type: 'uint32_t'>
	<returns: 'int64_t'>
	| carry t |
	carry := c asUInt64.
	0 to: n - 1 do: [:i |
		t := (a at: i) asUInt64 * m + carry.
		a at: i put: t asUInt32.
		carry := t >> 32].
	carry = 0 ifTrue: [^n].
	a at: n put: carry asUInt32.
	^n + 1
!
bigTimesPowerOf5: a size: n power: k
	"a := a * 5^k; answer its size."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<var: #k type: 'int64_t'>
	<returns: 'int64_t'>
	| size left m |
	size := n.
	left := k.
	[left >= 13] whileTrue: [
		size := self bigMul: a size: size by: 1220703125 add: 0.
		left := left - 13].
	m := 1.
	left timesRepeat: [m := m * 5].
	^self bigMul: a size: size by: m asUInt32 add: 0
!
bigShift: a size: n left: s
	"a := a << s; answer its size (the buffer has room for s // 32 + 1 more limbs)."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<var: #s type: 'int64_t'>
	<returns: 'int64_t'>
	| limbs bits size |
	n = 0 ifTrue: [^0].
	limbs := s quo: 32.
	bits := s rem: 32.
	a at: n + limbs put: ((a at: n - 1) asUInt64 >> (32 - bits)) asUInt32.
	n - 1 to: 1 by: -1 do: [:i |
		a at: i + limbs put: (((a at: i) asUInt64 << bits) bitOr: (a at: i - 1) asUInt64 >> (32 - bits)) asUInt32].
	a at: limbs put: ((a at: 0) asUInt64 << bits) asUInt32.
	0 to: limbs - 1 do: [:i | a at: i put: 0].
	size := n + limbs + 1.
	[size > 0 and: [(a at: size - 1) = 0]] whileTrue: [size := size - 1].
	^size
!
bigHalve: a size: n
	"a := a >> 1; answer its size."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| size |
	0 to: n - 2 do: [:i |
		a at: i put: (((a at: i) asUInt64 >> 1) bitOr: ((a at: i + 1) asUInt64 << 31)) asUInt32].
	n > 0 ifTrue: [a at: n - 1 put: (a at: n - 1) >> 1].
	size := n.
	[size > 0 and: [(a at: size - 1) = 0]] whileTrue: [size := size - 1].
	^size
!
bigCompare: a size: na with: b size: nb
	"-1, 0 or 1: a against b (sizes without leading zero limbs)."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #na type: 'int64_t'>
	<var: #b type: 'uint32_t *'>
	<var: #nb type: 'int64_t'>
	<returns: 'int32_t'>
	| i |
	na ~= nb ifTrue: [^na < nb ifTrue: [-1] ifFalse: [1]].
	i := na - 1.
	[i >= 0 and: [(a at: i) = (b at: i)]] whileTrue: [i := i - 1].
	i < 0 ifTrue: [^0].
	^(a at: i) < (b at: i) ifTrue: [-1] ifFalse: [1]
!
bigSubtract: b size: nb from: a size: na
	"a := a - b (a >= b); answer its size."
	<function>
	<var: #b type: 'uint32_t *'>
	<var: #nb type: 'int64_t'>
	<var: #a type: 'uint32_t *'>
	<var: #na type: 'int64_t'>
	<returns: 'int64_t'>
	| borrow t size |
	borrow := 0.
	0 to: na - 1 do: [:i |
		t := (a at: i) asInt64 - (i < nb ifTrue: [(b at: i) asInt64] ifFalse: [0]) - borrow.
		a at: i put: t asUInt32.
		borrow := t < 0 ifTrue: [1] ifFalse: [0]].
	size := na.
	[size > 0 and: [(a at: size - 1) = 0]] whileTrue: [size := size - 1].
	^size
!
bigQuotient: a size: na by: b size: nb work: w
	"Answer a // b, which must be below 2^56, leaving a rem: b in a (its limbs above stay zero). w: scratch for b << 55."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #na type: 'int64_t'>
	<var: #b type: 'uint32_t *'>
	<var: #nb type: 'int64_t'>
	<var: #w type: 'uint32_t *'>
	<returns: 'uint64_t'>
	| q size wn |
	0 to: nb - 1 do: [:i | w at: i put: (b at: i)].
	wn := self bigShift: w size: nb left: 55.
	size := na.
	q := 0 asUInt64.
	55 to: 0 by: -1 do: [:bit |
		(self bigCompare: a size: size with: w size: wn) >= 0 ifTrue: [
			size := self bigSubtract: w size: wn from: a size: size.
			q := q bitOr: 1 asUInt64 << bit].
		wn := self bigHalve: w size: wn].
	^q
!
bigDivide: a size: n bySmall: m
	"a := a // m; answer a rem: m."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<var: #m type: 'uint32_t'>
	<returns: 'uint32_t'>
	| rem t |
	rem := 0 asUInt64.
	n - 1 to: 0 by: -1 do: [:i |
		t := (rem << 32) bitOr: (a at: i).
		a at: i put: (t quo: m) asUInt32.
		rem := t rem: m].
	^rem asUInt32
!
bitLength: a size: n
	"The number of bits of a (n > 0 limbs, the top one not zero)."
	<function>
	<var: #a type: 'uint32_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| top bits |
	top := (a at: n - 1) asUInt64.
	bits := 0.
	[top ~= 0] whileTrue: [
		top := top >> 1.
		bits := bits + 1].
	^(n - 1) * 32 + bits
! !

!UefiLibM methodsFor: 'decimal'!
strtod: s end: endp
	"C's strtod, correctly rounded (half to even) as glibc's: white space, a sign, decimal digits with a point and an exponent, or inf, infinity, nan, nan(chars) in any case. No hexadecimal floats. endp (unless NULL) gets the end of what was converted, s if nothing was."
	<function>
	<var: #s type: 'const char *'>
	<var: #endp type: 'char **'>
	<returns: 'double'>
	| p i c neg bits j digits nd dropped exp10 sawDigit dig expv expNeg payload |
	p := self cCoerce: s to: 'uint8_t *'.
	i := 0.
	[(p at: i) = 32 or: [(p at: i) >= 9 and: [(p at: i) <= 13]]] whileTrue: [i := i + 1].
	neg := false.
	c := p at: i.
	(c = $- value or: [c = $+ value]) ifTrue: [
		neg := c = $- value.
		i := i + 1].
	bits := 0 asUInt64.
	(self at: p + i matches: (self cString: 'inf')) ifTrue: [
		i := i + 3.
		(self at: p + i matches: (self cString: 'inity')) ifTrue: [i := i + 5].
		bits := 16r7FF0000000000000.
		^self end: endp at: s + i value: bits negative: neg].
	(self at: p + i matches: (self cString: 'nan')) ifTrue: [
		i := i + 3.
		bits := 16r7FF8000000000000.
		(p at: i) = $( value ifTrue: [
			j := i + 1.
			[self isNanChar: (p at: j)] whileTrue: [j := j + 1].
			(p at: j) = $) value ifTrue: [
				payload := self nanPayload: p + i + 1 size: j - i - 1.
				bits := bits bitOr: (payload bitAnd: 16r7FFFFFFFFFFFF).
				i := j + 1]].
		^self end: endp at: s + i value: bits negative: neg].
	"the significant digits (at most 800, then whether a later one is not zero) and the decimal exponent"
	digits := self local: 'uint8_t[804]'.
	nd := 0.
	dropped := false.
	exp10 := 0.
	sawDigit := false.
	[(p at: i) >= 48 and: [(p at: i) <= 57]] whileTrue: [
		sawDigit := true.
		dig := (p at: i) - 48.
		(nd > 0 or: [dig ~= 0]) ifTrue: [
			nd < 800
				ifTrue: [
					digits at: nd put: dig.
					nd := nd + 1]
				ifFalse: [
					dig ~= 0 ifTrue: [dropped := true].
					exp10 := exp10 + 1]].
		i := i + 1].
	(p at: i) = $. value ifTrue: [
		i := i + 1.
		[(p at: i) >= 48 and: [(p at: i) <= 57]] whileTrue: [
			sawDigit := true.
			dig := (p at: i) - 48.
			(nd > 0 or: [dig ~= 0])
				ifTrue: [
					nd < 800
						ifTrue: [
							digits at: nd put: dig.
							nd := nd + 1.
							exp10 := exp10 - 1]
						ifFalse: [dig ~= 0 ifTrue: [dropped := true]]]
				ifFalse: [exp10 := exp10 - 1].
			i := i + 1]].
	sawDigit ifFalse: [
		endp notNull ifTrue: [endp value: (self cCoerce: s to: 'char *')].
		^0.0].
	((p at: i) bitOr: 32) = $e value ifTrue: [
		j := i + 1.
		expNeg := false.
		((p at: j) = $- value or: [(p at: j) = $+ value]) ifTrue: [
			expNeg := (p at: j) = $- value.
			j := j + 1].
		((p at: j) >= 48 and: [(p at: j) <= 57]) ifTrue: [
			expv := 0.
			[(p at: j) >= 48 and: [(p at: j) <= 57]] whileTrue: [
				expv < 100000000 ifTrue: [expv := expv * 10 + ((p at: j) - 48)].
				j := j + 1].
			exp10 := expNeg ifTrue: [exp10 - expv] ifFalse: [exp10 + expv].
			i := j]].
	dropped ifTrue: [
		"a nonzero digit beyond the 800th: a 1 in its place decides the rounding the same way"
		digits at: nd put: 1.
		nd := nd + 1.
		exp10 := exp10 - 1].
	bits := self decimal: digits count: nd exponent: exp10.
	^self end: endp at: s + i value: bits negative: neg
!
end: endp at: e value: bits negative: neg
	endp notNull ifTrue: [endp value: (self cCoerce: e to: 'char *')].
	^self doubleFromBits: (neg ifTrue: [bits bitOr: 16r8000000000000000] ifFalse: [bits])
!
at: p matches: w
	"Whether the bytes at p begin with the lowercase letters of the C string w, in any case."
	| k |
	k := 0.
	[(w at: k) ~= 0 and: [((p at: k) bitOr: 32) = (w at: k) asInt32]] whileTrue: [k := k + 1].
	^(w at: k) = 0
!
isNanChar: c
	^(c >= 48 and: [c <= 57]) or: [((c bitOr: 32) >= 97 and: [(c bitOr: 32) <= 122]) or: [c = 95]]
!
digitValue: c
	"The value of c as a digit of base up to 36; 99 if it is none."
	(c >= 48 and: [c <= 57]) ifTrue: [^c - 48].
	((c bitOr: 32) >= 97 and: [(c bitOr: 32) <= 122]) ifTrue: [^(c bitOr: 32) - 87].
	^99
!
nanPayload: p size: n
	"glibc's NaN payload of nan(chars): the n chars read by strtoull with base 0 (all of them, else 0)."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'uint64_t'>
	| j base v over d |
	j := 0.
	base := 10 asUInt64.
	(n > 0 and: [(p at: 0) = 48]) ifTrue: [
		(n > 2 and: [((p at: 1) bitOr: 32) = 120 and: [(self digitValue: (p at: 2)) < 16]])
			ifTrue: [
				base := 16 asUInt64.
				j := 2]
			ifFalse: [base := 8 asUInt64]].
	v := 0 asUInt64.
	over := false.
	[j < n and: [(self digitValue: (p at: j)) asUInt64 < base]] whileTrue: [
		d := (self digitValue: (p at: j)) asUInt64.
		v > ((16rFFFFFFFFFFFFFFFF asUInt64 - d) quo: base)
			ifTrue: [over := true]
			ifFalse: [v := v * base + d].
		j := j + 1].
	j < n ifTrue: [^0 asUInt64].
	over ifTrue: [^16rFFFFFFFFFFFFFFFF asUInt64].
	^v
!
decimal: digits count: count exponent: exponent
	"The bits of the double nearest (half to even) to digits (count decimal digits, the first not zero) times 10^exponent, positive or zero."
	<function>
	<var: #digits type: 'uint8_t *'>
	<var: #count type: 'int64_t'>
	<var: #exponent type: 'int64_t'>
	<returns: 'uint64_t'>
	| n e v p num nn den dn work k chunk mult t e2 sh q sticky mant w |
	n := count.
	e := exponent.
	[n > 0 and: [(digits at: n - 1) = 0]] whileTrue: [
		n := n - 1.
		e := e + 1].
	n = 0 ifTrue: [^0 asUInt64].
	(n <= 15 and: [e >= -22 and: [e <= 22]]) ifTrue: [
		"Clinger's fast path: the digits and 10^|e| are doubles, one operation rounds once"
		v := 0.
		0 to: n - 1 do: [:i | v := v * 10 + (digits at: i)].
		p := 1.0.
		(e < 0 ifTrue: [e negated] ifFalse: [e]) timesRepeat: [p := p * 10.0].
		^self bitsOfDouble: (e < 0 ifTrue: [v asFloat / p] ifFalse: [v asFloat * p])].
	"at least 10^310, below 10^-324"
	n + e > 310 ifTrue: [^16r7FF0000000000000 asUInt64].
	n + e < -324 ifTrue: [^0 asUInt64].
	"the value is num / den * 2^e: num = digits * 5^e or den = 5^-e"
	num := self local: 'uint32_t[132]'.
	den := self local: 'uint32_t[132]'.
	work := self local: 'uint32_t[132]'.
	nn := 0.
	k := 0.
	[k < n] whileTrue: [
		chunk := 0.
		mult := 1.
		[mult < 1000000000 and: [k < n]] whileTrue: [
			chunk := chunk * 10 + (digits at: k).
			mult := mult * 10.
			k := k + 1].
		nn := self bigMul: num size: nn by: mult asUInt32 add: chunk asUInt32].
	den at: 0 put: 1.
	dn := 1.
	e >= 0
		ifTrue: [nn := self bigTimesPowerOf5: num size: nn power: e]
		ifFalse: [dn := self bigTimesPowerOf5: den size: dn power: e negated].
	"2^(t-1) < value < 2^(t+1): the quotient num * 2^(e - e2) / den has 55 or 56 bits"
	t := (self bitLength: num size: nn) - (self bitLength: den size: dn) + e.
	e2 := t - 55.
	sh := e - e2.
	sh >= 0
		ifTrue: [nn := self bigShift: num size: nn left: sh]
		ifFalse: [dn := self bigShift: den size: dn left: sh negated].
	q := self bigQuotient: num size: nn by: den size: dn work: work.
	sticky := false.
	0 to: nn - 1 do: [:i | (num at: i) ~= 0 ifTrue: [sticky := true]].
	"53 bits and a rounding bit, fewer for a subnormal (whose last bit is 2^-1074)"
	[q >= 16r40000000000000] whileTrue: [
		(q bitAnd: 1) ~= 0 ifTrue: [sticky := true].
		q := q >> 1.
		e2 := e2 + 1].
	e2 < -1075 ifTrue: [
		sh := -1075 - e2.
		sh >= 54
			ifTrue: [
				q ~= 0 ifTrue: [sticky := true].
				q := 0 asUInt64]
			ifFalse: [
				(q bitAnd: (1 asUInt64 << sh) - 1) ~= 0 ifTrue: [sticky := true].
				q := q >> sh].
		e2 := -1075].
	mant := q >> 1.
	((q bitAnd: 1) ~= 0 and: [sticky or: [(mant bitAnd: 1) ~= 0]]) ifTrue: [mant := mant + 1].
	"a carry out of the mantissa increments the exponent; the exponent field of a subnormal is 0"
	w := ((e2 + 1075) asUInt64 << 52) + mant.
	w >= 16r7FF0000000000000 ifTrue: [^16r7FF0000000000000 asUInt64].
	^w
!
decimalDigits: bits into: d info: info
	"The exact decimal value of the finite double with these bits: its digits (0 to 9, no leading or trailing zeros) into d, their number into info[0] and the position of the decimal point into info[1] (the value is 0.d0 d1 d2 ... * 10^info[1]); none for zero."
	<function>
	<var: #bits type: 'uint64_t'>
	<var: #d type: 'uint8_t *'>
	<var: #info type: 'int32_t *'>
	<var: #nb type: 'int64_t'>
	| ex m e k big nb tmp nt chunk ip frac li off w nd dp lead |
	ex := ((bits >> 52) bitAnd: 16r7FF) asInt64.
	m := bits bitAnd: 16rFFFFFFFFFFFFF.
	e := -1074.
	ex ~= 0 ifTrue: [
		m := m bitOr: 16r10000000000000.
		e := ex - 1075].
	info at: 0 put: 0.
	info at: 1 put: 0.
	m = 0 ifTrue: [^self].
	k := 0.
	e < 0 ifTrue: [k := e negated].
	big := self local: 'uint32_t[40]'.
	tmp := self local: 'uint8_t[320]'.
	nt := 0.
	e >= 0
		ifTrue: [
			"an integer: m << e in decimal, 9 digits at a time from the right"
			big at: 0 put: m asUInt32.
			big at: 1 put: (m >> 32) asUInt32.
			nb := (m >> 32) = 0 ifTrue: [1] ifFalse: [2].
			nb := self bigShift: big size: nb left: e.
			[nb > 0] whileTrue: [
				chunk := self bigDivide: big size: nb bySmall: 1000000000.
				[nb > 0 and: [(big at: nb - 1) = 0]] whileTrue: [nb := nb - 1].
				9 timesRepeat: [
					tmp at: nt put: (chunk rem: 10).
					chunk := chunk quo: 10.
					nt := nt + 1]]]
		ifFalse: [
			ip := k >= 53 ifTrue: [0 asUInt64] ifFalse: [m >> k].
			[ip > 0] whileTrue: [
				tmp at: nt put: (ip rem: 10).
				ip := ip quo: 10.
				nt := nt + 1]].
	nd := 0.
	nt - 1 to: 0 by: -1 do: [:i |
		d at: nd put: (tmp at: i).
		nd := nd + 1].
	dp := nd.
	e < 0 ifTrue: [
		"the fraction (k bits) times 10^9 at a time: the bits above 2^k are the next 9 digits"
		frac := k >= 53 ifTrue: [m] ifFalse: [m bitAnd: (1 asUInt64 << k) - 1].
		big at: 0 put: frac asUInt32.
		big at: 1 put: (frac >> 32) asUInt32.
		nb := frac = 0 ifTrue: [0] ifFalse: [(frac >> 32) = 0 ifTrue: [1] ifFalse: [2]].
		li := k quo: 32.
		off := k rem: 32.
		[nb > 0] whileTrue: [
			nb := self bigMul: big size: nb by: 1000000000 add: 0.
			w := ((big at: li) asUInt64 bitOr: (big at: li + 1) asUInt64 << 32) >> off.
			big at: li put: ((big at: li) asUInt64 bitAnd: (1 asUInt64 << off) - 1) asUInt32.
			big at: li + 1 put: 0.
			nb > (li + 1) ifTrue: [nb := li + 1].
			[nb > 0 and: [(big at: nb - 1) = 0]] whileTrue: [nb := nb - 1].
			8 to: 0 by: -1 do: [:j |
				d at: nd + j put: (w rem: 10).
				w := w quo: 10].
			nd := nd + 9]].
	lead := 0.
	[lead < nd and: [(d at: lead) = 0]] whileTrue: [lead := lead + 1].
	lead > 0 ifTrue: [
		0 to: nd - lead - 1 do: [:i | d at: i put: (d at: i + lead)].
		nd := nd - lead.
		dp := dp - lead].
	[nd > 0 and: [(d at: nd - 1) = 0]] whileTrue: [nd := nd - 1].
	info at: 0 put: nd asInt32.
	info at: 1 put: dp asInt32
!
roundDigits: d info: info keep: keep
	"Round the digits (d, info as decimalDigits:into:info: leaves them) to their first keep (half to even: the digits are exact); a carry out of the first moves the point."
	<function>
	<var: #d type: 'uint8_t *'>
	<var: #info type: 'int32_t *'>
	<var: #keep type: 'int64_t'>
	| nd dp up i |
	nd := (info at: 0) asInt64.
	dp := (info at: 1) asInt64.
	keep >= nd ifTrue: [^self].
	keep < 0 ifTrue: [
		info at: 0 put: 0.
		^self].
	up := keep = 0
		ifTrue: [(d at: 0) > 5 or: [(d at: 0) = 5 and: [nd > 1]]]
		ifFalse: [(d at: keep) > 5 or: [(d at: keep) = 5 and: [nd > (keep + 1) or: [((d at: keep - 1) bitAnd: 1) ~= 0]]]].
	nd := keep.
	up ifTrue: [
		i := keep - 1.
		[i >= 0 and: [(d at: i) = 9]] whileTrue: [
			d at: i put: 0.
			i := i - 1].
		i < 0
			ifTrue: [
				d at: 0 put: 1.
				nd := 1.
				dp := dp + 1]
			ifFalse: [d at: i put: (d at: i) + 1]].
	[nd > 0 and: [(d at: nd - 1) = 0]] whileTrue: [nd := nd - 1].
	info at: 0 put: nd asInt32.
	info at: 1 put: dp asInt32
!
emit: ch into: buf size: n at: pos
	"Store ch at buf[pos] if it leaves room for the NUL; answer the next position."
	<function>
	<var: #ch type: 'int64_t'>
	<var: #buf type: 'char *'>
	<var: #n type: 'size_t'>
	<var: #pos type: 'int64_t'>
	<returns: 'int64_t'>
	(pos + 1) asUInt64 < n ifTrue: [buf at: pos put: ch].
	^pos + 1
!
fixed: d info: info fraction: f into: buf size: n at: pos
	"The digits in the style of %f with f digits after the point (zeros beyond the digits)."
	<function>
	<var: #d type: 'uint8_t *'>
	<var: #info type: 'int32_t *'>
	<var: #f type: 'int64_t'>
	<var: #buf type: 'char *'>
	<var: #n type: 'size_t'>
	<var: #pos type: 'int64_t'>
	<returns: 'int64_t'>
	| nd dp at i |
	nd := (info at: 0) asInt64.
	dp := (info at: 1) asInt64.
	at := pos.
	dp <= 0
		ifTrue: [at := self emit: $0 value into: buf size: n at: at]
		ifFalse: [
			0 to: dp - 1 do: [:j |
				at := self emit: (j < nd ifTrue: [(d at: j) + 48] ifFalse: [48]) into: buf size: n at: at]].
	f > 0 ifTrue: [
		at := self emit: $. value into: buf size: n at: at.
		0 to: f - 1 do: [:j |
			i := dp + j.
			at := self emit: ((i >= 0 and: [i < nd]) ifTrue: [(d at: i) + 48] ifFalse: [48]) into: buf size: n at: at]].
	^at
!
scientific: d info: info fraction: f upper: upper into: buf size: n at: pos
	"The digits in the style of %e with f digits after the point and an exponent of at least two digits."
	<function>
	<var: #d type: 'uint8_t *'>
	<var: #info type: 'int32_t *'>
	<var: #f type: 'int64_t'>
	<var: #upper type: 'bool'>
	<var: #buf type: 'char *'>
	<var: #n type: 'size_t'>
	<var: #pos type: 'int64_t'>
	<returns: 'int64_t'>
	| nd dp at x10 ax |
	nd := (info at: 0) asInt64.
	dp := (info at: 1) asInt64.
	at := self emit: (nd > 0 ifTrue: [(d at: 0) + 48] ifFalse: [48]) into: buf size: n at: pos.
	f > 0 ifTrue: [
		at := self emit: $. value into: buf size: n at: at.
		1 to: f do: [:i |
			at := self emit: (i < nd ifTrue: [(d at: i) + 48] ifFalse: [48]) into: buf size: n at: at]].
	at := self emit: (upper ifTrue: [$E value] ifFalse: [$e value]) into: buf size: n at: at.
	x10 := nd = 0 ifTrue: [0] ifFalse: [dp - 1].
	at := self emit: (x10 < 0 ifTrue: [$- value] ifFalse: [$+ value]) into: buf size: n at: at.
	ax := x10 < 0 ifTrue: [x10 negated] ifFalse: [x10].
	ax >= 100 ifTrue: [at := self emit: (ax quo: 100) + 48 into: buf size: n at: at].
	at := self emit: ((ax quo: 10) rem: 10) + 48 into: buf size: n at: at.
	^self emit: (ax rem: 10) + 48 into: buf size: n at: at
!
formatDouble: x precision: p conversion: c into: buf size: n
	"snprintf(buf, n, ""%.*<c>"", p, x) for c one of $e $E $f $F $g $G (p < 0: 6), as glibc prints it: the exact binary value rounded half to even. Writes at most n - 1 chars and a NUL (if n > 0); answers the length of the whole conversion."
	<function>
	<var: #x type: 'double'>
	<var: #p type: 'int'>
	<var: #c type: 'int'>
	<var: #buf type: 'char *'>
	<var: #n type: 'size_t'>
	<returns: 'int'>
	| bits upper conv prec pos d info nd dp x10 |
	bits := self bitsOfDouble: x.
	upper := c = $E value or: [c = $F value or: [c = $G value]].
	conv := upper ifTrue: [c + 32] ifFalse: [c].
	prec := p < 0 ifTrue: [6] ifFalse: [p asInt64].
	pos := 0.
	(bits >> 63) ~= 0 ifTrue: [pos := self emit: $- value into: buf size: n at: pos].
	(bits bitAnd: 16r7FF0000000000000) = 16r7FF0000000000000
		ifTrue: [
			(bits bitAnd: 16rFFFFFFFFFFFFF) = 0
				ifTrue: [
					pos := self emit: (upper ifTrue: [$I value] ifFalse: [$i value]) into: buf size: n at: pos.
					pos := self emit: (upper ifTrue: [$N value] ifFalse: [$n value]) into: buf size: n at: pos.
					pos := self emit: (upper ifTrue: [$F value] ifFalse: [$f value]) into: buf size: n at: pos]
				ifFalse: [
					pos := self emit: (upper ifTrue: [$N value] ifFalse: [$n value]) into: buf size: n at: pos.
					pos := self emit: (upper ifTrue: [$A value] ifFalse: [$a value]) into: buf size: n at: pos.
					pos := self emit: (upper ifTrue: [$N value] ifFalse: [$n value]) into: buf size: n at: pos]]
		ifFalse: [
			d := self local: 'uint8_t[1200]'.
			info := self local: 'int32_t[2]'.
			self decimalDigits: bits into: d info: info.
			conv = $g value
				ifTrue: [
					"P significant digits; %f style if the exponent X is -4 <= X < P, else %e; no trailing zeros"
					prec = 0 ifTrue: [prec := 1].
					self roundDigits: d info: info keep: prec.
					nd := (info at: 0) asInt64.
					dp := (info at: 1) asInt64.
					x10 := nd = 0 ifTrue: [0] ifFalse: [dp - 1].
					(x10 < prec and: [x10 >= -4])
						ifTrue: [pos := self fixed: d info: info fraction: (nd > dp ifTrue: [nd - dp] ifFalse: [0]) into: buf size: n at: pos]
						ifFalse: [pos := self scientific: d info: info fraction: nd - 1 upper: upper into: buf size: n at: pos]]
				ifFalse: [
					conv = $e value
						ifTrue: [
							self roundDigits: d info: info keep: prec + 1.
							pos := self scientific: d info: info fraction: prec upper: upper into: buf size: n at: pos]
						ifFalse: [
							self roundDigits: d info: info keep: (info at: 1) asInt64 + prec.
							pos := self fixed: d info: info fraction: prec into: buf size: n at: pos]]].
	n > 0 ifTrue: [
		pos asUInt64 < n
			ifTrue: [buf at: pos put: 0]
			ifFalse: [buf at: n - 1 put: 0]].
	^pos asInt32
! !
