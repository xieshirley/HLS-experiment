// =====================================================================
// matmul.h 閳ユ柡锟斤拷 閸忣剙鍙＄�规矮绠熼敍姘辩叐闂冧絻顫夊Ο鈥茬瑢閺佺増宓佺猾璇茬��
// 鐠囧墽鈻奸敍姘剁彯鐏炲倹顐肩紒鐓庢値閹讹拷閺堫垽绱欓惍鏃傗敀閻㈢喎鐤勬宀嬬礆
// 鐠囧瓨妲戦敍姘閺堝鐤勬宀�澧楅張顒�鍙￠悽銊ф祲閸氬瞼娈戞い璺虹湴閸戣姤鏆熼幒銉ュ經 matmul_top閿涳拷
//       娴狅拷"鐎圭偟骞囬弬鐟扮础 + 娴兼ê瀵查幐鍥︽姢(#pragma)"娑撳秴鎮撻敍灞肩┒娴滃孩铆閸氭垵顕В鏃傛偅閸氬牏绮ㄩ弸婧匡拷锟�
// =====================================================================
#ifndef MATMUL_H
#define MATMUL_H

#include <ap_int.h>          // Vivado HLS 閹绘劒绶甸惃鍕崲閹板繋缍呯�硅姤鏆ｉ弫鎵閸ㄥ绨�

#define N 32                // 閻晠妯�缂佹潙瀹抽敍娆伴妴涓呴妴涓� 閸у洣璐� N x N
//typedef ap_int<16> data_t;
//typedef ap_int<48> acc_t;
typedef int data_t;          // 閸╄櫣顢呴悧鍫熸殶閹诡喚琚崹瀣剁窗32 娴ｏ拷 int
                             // 閿涘澊5_fixed16 鐎圭偤鐛欑亸鍡樻暭娑擄拷 ap_int<16>閿涘苯顕В鏃囩カ濠ф劖绉烽懓妤嬬礆
typedef int dtype;
// 妞よ泛鐪伴崙鑺ユ殶閿涙俺顓哥粻锟� C = A x B
//void matmul_top(data_t A[N][N], data_t B[N][N], acc_t C[N][N]);
void matmul_top(dtype A[N][N], dtype B[N][N], dtype C[N][N]);
#endif // MATMUL_H
