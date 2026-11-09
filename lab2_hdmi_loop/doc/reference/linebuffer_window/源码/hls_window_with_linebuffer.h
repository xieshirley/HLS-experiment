#include <hls_video.h>
/* Template class of hls_window_with_linebuffer */
// ROWS     : number of rows in a window
// COLS     : number of cols in a window
// MAX_COLS : number of cols in a row
// T        : data type of a window

template<int ROWS, int COLS, int MAX_COLS, typename T>
class hls_window_with_linebuffer {
public:
	hls_window_with_linebuffer() { };
    void insert(T val);
    T getval(int row, int col);
    hls::LineBuffer<ROWS,MAX_COLS,T,0> lb;
    hls::Window<ROWS,COLS,T> w;
};

template<int ROWS, int COLS, int MAX_COLS, typename T>
void hls_window_with_linebuffer<ROWS, COLS, MAX_COLS, T>::insert(T val)
{
#pragma HLS inline
	T tmp ;
	int i ;
	static int col ;
	w.shift_right();
	tmp = val ;
	w.insert(tmp,0,0) ;
	for(i=1;i<ROWS;i++)
	{
		w.insert(lb.getval(i-1,col),i,0) ;
	}
	lb.shift_down(col);
	lb.insert_bottom(tmp,col);
	col++;
	if(col>=MAX_COLS)
		col = 0 ;
}

template<int ROWS, int COLS, int MAX_COLS, typename T>
T hls_window_with_linebuffer<ROWS, COLS, MAX_COLS, T>::getval(int row, int col)
{
#pragma HLS inline
	return w.getval(row, col) ;
}
