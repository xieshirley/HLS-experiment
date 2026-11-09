#include <ap_int.h>
#include <hls_video.h>

template<int ROWS, int COLS, int MAX_COLS, typename T>
class hls_window_with_linebuffer {
public:
	T w[ROWS][COLS] ;
	int col ;
	hls::LineBuffer<ROWS-1, MAX_COLS, T, 0> lb ;
	hls_window_with_linebuffer() {
		int i,j ;
#pragma HLS ARRAY_PARTITION variable=w dim=0 complete
		col = 0 ;
		for(i=0;i<ROWS;i++)
#pragma HLS UNROLL
			for(j=0;j<COLS;j++)
#pragma HLS UNROLL
				w[i][j] = 0 ;
	};
	void insert( T val )
	{
#pragma HLS inline
		int i,j ;
		T c[ROWS] ;
#pragma HLS ARRAY_PARTITION variable=c dim=0 complete
		c[0] = val ;
		for(i=1;i<ROWS;i++)
#pragma HLS UNROLL
			c[i] = lb.getval(i-1,col) ;
		for(i=0;i<ROWS;i++)
#pragma HLS UNROLL
			for(j=COLS-1;j>0;j--)
#pragma HLS UNROLL
				w[i][j] = w[i][j-1] ;
		for(i=0;i<ROWS;i++)
#pragma HLS UNROLL
			w[i][0] = c[i] ;
		lb.shift_down(col);
		lb.insert_bottom(c[0],col);
		if(col>=MAX_COLS-1)
			col = 0 ;
		else
			col++;
	}
};

