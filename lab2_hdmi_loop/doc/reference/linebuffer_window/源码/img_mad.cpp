#include <ap_int.h>
#include <stdio.h>
#include "hls_window_with_linebuffer.h"

// REF_ROWS = REF_COLS = 64
// MAD_ROWS = searching range X max
// MAD_COLS = searching range Y max
template<int IMG_ROWS, int IMG_COLS, int REF_ROWS, int REF_COLS, int MAD_ROWS, int MAD_COLS, typename T1, typename T2>
void img_mad(T1 img[IMG_ROWS][IMG_COLS], T1 ref[REF_ROWS][REF_COLS], ap_uint<1> mask[REF_ROWS][REF_COLS], T2 mad[MAD_ROWS][MAD_COLS], ap_uint<6>subi, ap_uint<6>subj)
{
#pragma HLS ARRAY_PARTITION variable=ref complete dim=0
#pragma HLS ARRAY_PARTITION variable=mask complete dim=0
	static hls_window_with_linebuffer< REF_ROWS, REF_COLS, MAD_COLS+REF_COLS-1, T1 > wlb ;
#pragma HLS DEPENDENCE variable=wlb array inter false
#pragma HLS DEPENDENCE variable=wlb array intra false
	int i,j,ii,jj,t;
	T2 d ;
	for(i=0;i<MAD_ROWS+REF_ROWS-1;i++)
		for(j=0;j<MAD_COLS+REF_COLS-1;j++)
		{
#pragma HLS PIPELINE II=1
			wlb.insert(img[i+(subi<<4)][j+(subj<<4)]);
			d = 0 ;
			for(ii=0;ii<REF_ROWS;ii++)
#pragma HLS UNROLL
				for(jj=0;jj<REF_COLS;jj++)
				{
#pragma HLS UNROLL
//					if(ii==0&&jj==0)
//						d = mask[ii][jj]*abs( ref[ii][jj] - wlb.getval(ii,jj) );
//					else
						d += mask[ii][jj]*abs( ref[ii][jj] - wlb.getval(ii,jj) );
				}
			if(i>=REF_ROWS-1&&j>=REF_COLS-1)
				mad[i-REF_ROWS+1][j-REF_COLS+1] += d ;
			/*
			if(i>=100&&i<104&&j>=100&&j<104)
			{
				printf("i=%5d,j=%5d\n",i,j);
				for(ii=0;ii<REF_ROWS;ii++)
				{
					for(jj=0;jj<REF_COLS;jj++)
					{
						t = wlb.getval(ii,jj) ;
						printf("%5d",t);
					}
					printf("\n");
				}
			}
			*/
		}
}

#define IMG_ROWS 192
#define IMG_COLS 320
#define REF_ROWS 16
#define REF_COLS 16
#define MAD_ROWS 128
#define MAD_COLS 256

void read_mask( ap_uint<1> mask64x64[64][64], ap_uint<1> mask16x16[16][16] , int i, int j )
{
	for(int ii=0;ii<16;ii++)
		for(int jj=0;jj<16;jj++)
			mask16x16[ii][jj] = mask64x64[(i<<4)+ii][(j<<4)+jj] ;
}
void read_ref( ap_uint<8> ref64x64[64][64], ap_uint<8> ref16x16[16][16] , int i, int j )
{
	for(int ii=0;ii<16;ii++)
		for(int jj=0;jj<16;jj++)
			ref16x16[ii][jj] = ref64x64[(i<<4)+ii][(j<<4)+jj] ;
}

void test(ap_uint<8> img[IMG_ROWS][IMG_COLS], ap_uint<8> ref[64][64], ap_uint<1> mask[64][64], ap_uint<20> &min_val, ap_uint<8> &min_x, ap_uint<8> &min_y )
{
	int i,j,min_v_t, min_x_t,min_y_t,ii,jj,t;
	ap_uint<1> mask16x16[16][16] ;
	ap_uint<8> ref16x16[16][16] ;
	ap_uint<20> z[MAD_ROWS][MAD_COLS] ;

	printf("image : \n");
	for(i=0;i<IMG_ROWS;i++)
	{
		printf("i=%4d : ",i);
		for(j=0;j<IMG_COLS;j++)
		{
			t= img[i][j];
			printf("%4d",t);
		}
		printf("\n");
	}

	for(i=0;i<MAD_ROWS;i++)
		for(j=0;j<MAD_COLS;j++)
#pragma HLS PIPELINE
			z[i][j] = 0 ;
	for(i=0;i<4;i++)
		for(j=0;j<4;j++)
		{
			printf("i=%4d,j=%d\n",i,j);
			read_mask(mask,mask16x16,i,j) ;
			read_ref(ref,ref16x16,i,j) ;

//			if(i==0&&j==0)
			{
			printf("mask : \n");
			for(ii=0;ii<REF_ROWS;ii++)
			{
				printf("i=%4d : ",ii);
				for(jj=0;jj<REF_COLS;jj++)
				{
					t= mask[ii][jj];
					printf("%4d",t);
				}
				printf("\n");
			}
			}

			img_mad< IMG_ROWS, IMG_COLS, REF_ROWS, REF_COLS, MAD_ROWS, MAD_COLS, ap_uint<8>, ap_uint<20> > ( img, ref16x16, mask16x16, z, i, j ) ;

//			if(i==0&&j==0)
			{
			printf("mad : \n");
			printf("i=%4d : ",0);
			for(jj=0;jj<MAD_COLS;jj++)
				printf("%5d",jj);
			printf("\n");
			for(ii=0;ii<MAD_ROWS;ii++)
			{
				printf("i=%4d : ",ii);
				for(jj=0;jj<MAD_COLS;jj++)
				{
					t= z[ii][jj];
					printf("%5d",t);
				}
				printf("\n");
			}
			}

		}
	min_v_t = 64*64*255-1;
	min_x_t = 128 ;
	min_y_t = 64  ;

	for(i=0;i<MAD_ROWS;i++)
		for(j=0;j<MAD_COLS;j++)
#pragma HLS PIPELINE
			if(z[i][j]<min_v_t)
			{
				min_v_t = z[i][j] ;
				min_x_t = j ;
				min_y_t = i ;
			}
	min_val = min_v_t ;
	min_x   = min_x_t ;
	min_y   = min_y_t ;
}
