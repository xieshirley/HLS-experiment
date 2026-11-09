/*****************************************************************************
 * Modified from xilinx hls_video_mem.h
 * Function : window, linebuffer and window_with_linebuffer
 * History  :
 * 	1.0.0 : 林三虎，2016年05月26日，新建
 *****************************************************************************/


/* Template class of Window */
template<int ROWS, int COLS, typename T>
class HT_Window {
public:
	HT_Window() {
#pragma HLS ARRAY_PARTITION variable=val dim=1 complete
#pragma HLS ARRAY_PARTITION variable=val dim=2 complete
    };
    void shift_right();
    void shift_left();
    void shift_up();
    void shift_down();
    void insert(T value, int row, int col);
    void insert_bottom(T value[COLS]);
    void insert_top(T value[COLS]);
    void insert_left(T value[ROWS]);
    void insert_right(T value[ROWS]);
    T& getval(int row, int col);
    T& operator ()(int row, int col);

    T val[ROWS][COLS];
};

/* Member functions of Window class */

/* +---+---+-...-+---+---+
 * |   |   |     |   |   | R-1
 * +---+---+-...-+---+---+  
 * |   |   |     |   |   | R-2
 * +---+---+-...-+---+---+
 *   ...     ...    ...
 * +---+---+-...-+---+---+
 * |   |   |     |   |   | 1
 * +---+---+-...-+---+---+  
 * |   |   |     |   |   | 0
 * +---+---+-...-+---+---+
 *  C-1 C-2        1   0  (origin is at bottom-right point)
 */


/* Window shift left
 * Moves all the contents of the window horizontally (contents shift right)
 * Assumes new values will be placed in column = COLS-1
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::shift_left() {
#pragma HLS inline
    int i, j;
    for(i = 0; i < ROWS; i++) {
#pragma HLS unroll
        for(j = 0; j < COLS-1; j++) {
#pragma HLS unroll
            val[i][j] = val[i][j+1];
        }
    }
}

/* Window shift right
 * Moves all the contents of the window horizontally (contents shift left)
 * Assumes new values will be placed in column = 0
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::shift_right() {
#pragma HLS inline
    int i, j;
    for(i = 0; i < ROWS; i++) {
#pragma HLS unroll
        for(j = COLS-1; j > 0; j--) {
#pragma HLS unroll
            val[i][j] = val[i][j-1];
        }
    }
}

/* Window shift up
 * Moves all the contents of the window vertically (contents shift down)
 * Assumes new values will be placed in row = ROWS-1
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::shift_up() {
#pragma HLS inline
    int i, j;
    for(i = 0; i < ROWS-1; i++) {
#pragma HLS unroll
        for(j = 0; j < COLS; j++) {
#pragma HLS unroll
            val[i][j] = val[i+1][j];
        }
    }
}

/* Window shift down
 * Moves all the contents of the window vertically (contents shift up)
 * Assumes new values will be placed in row = 0
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::shift_down() {
#pragma HLS inline
    int i, j;
    for(i = ROWS-1; i > 0; i--) {
#pragma HLS unroll
        for(j = 0; j < COLS; j++) {
#pragma HLS unroll
            val[i][j] = val[i-1][j];
        }
    }
}

/* Window insert
 * Inserts a new value at any location of the window
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::insert(T value, int row, int col) {
#pragma HLS inline
//    assert(row >= 0 && row < ROWS && col >= 0 && col < COLS);
    val[row][col] = value;
}

/* Window insert top
 * Inserts a set of values in row ROWS-1 of the window
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::insert_top(T value[COLS]) {
#pragma HLS inline
    int j;
    for(j = 0; j < COLS; j++) {
#pragma HLS unroll
        val[ROWS-1][j] = value[j];
    }
}

/* Window insert bottom
 * Inserts a set of values in row 0 of the window
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::insert_bottom(T value[COLS]) {
#pragma HLS inline
    int j;
    for(j = 0; j < COLS; j++) {
#pragma HLS unroll
        val[0][j] = value[j];
    }
}

/* Window insert left
 * Inserts a set of values in column COLS-1 of the window
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::insert_left(T value[ROWS]) {
#pragma HLS inline
    int i;
    for(i = 0; i < ROWS; i++) {
#pragma HLS unroll
        val[i][COLS-1] = value[i];
    }
}

/* Window insert right
 * Inserts a set of values in column 0 of the window
 */
template<int ROWS, int COLS, typename T> void HT_Window<ROWS, COLS, T>::insert_right(T value[ROWS]) {
#pragma HLS inline
    int i;
    for(i = 0; i < ROWS; i++) {
#pragma HLS unroll
        val[i][0] = value[i];
    }
}

/* Window getval
 * Returns the data value in the window at position row, col
 */
template<int ROWS, int COLS, typename T> T& HT_Window<ROWS, COLS, T>::getval(int row, int col) {
#pragma HLS inline
//    assert(row >= 0 && row < ROWS && col >= 0 && col < COLS);
    return val[row][col];
}

/* Window getval
 * Returns the data value in the window at position row, col
 */
template<int ROWS, int COLS, typename T> T& HT_Window<ROWS, COLS, T>::operator ()(int row, int col) {
#pragma HLS inline
    return getval(row, col);
}

/* Template class of Line Buffer */
template<int ROWS, int COLS, typename T, int RESHAPE=0>
class HT_LineBuffer;

template<int ROWS, int COLS, typename T>
class HT_LineBuffer<ROWS, COLS, T, 0> {
public:
	HT_LineBuffer() {
#pragma HLS array_partition variable=val dim=1 complete
#pragma HLS dependence variable=val inter false
#pragma HLS dependence variable=val intra false
    };
    void shift_up(int col);
    void shift_down(int col);
    void insert_bottom(T value, int col);
    void insert_top(T value, int col);
    T& getval(int row, int col);
    T& operator ()(int row, int col);

    T val[ROWS][COLS];
};

/* Member functions of LineBuffer class */

/*     +---+---+-... ...-+---+---+
 * R-1 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+  
 * R-2 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+
 *       ...     ... ...   ...
 *     +---+---+-... ...-+---+---+
 *   1 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+  
 *   0 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+
 *       0   1   ... ...  C-2 C-1   (origin is at bottom-left point)
 */

/* Member functions of LineBuffer class */

/* Line buffer shift down
 * Assumes new data pixel will be entered at the bottom of the line buffer
 * The bottom is row = 0
 */
template<int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T>::shift_down(int col) {
#pragma HLS inline 
//    assert(col >= 0 && col < COLS);
    int i;
    for(i = ROWS-1; i > 0; i--) {
#pragma HLS unroll
        val[i][col] = val[i-1][col];
    }
}

/* Line buffer shift up
 * Assumes new data pixel will be entered at the top of the line buffer
 * The top is row = ROWS-1
 */
template<int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T>::shift_up(int col) {
#pragma HLS inline
//    assert(col >= 0 && col < COLS);
    int i;
    for(i = 0; i < ROWS-1; i++) {
#pragma HLS unroll
        val[i][col] = val[i+1][col];
    }
}

/* Line buffer insert bottom
 * Inserts a new value in the bottom row of the line buffer at column = col
 * The bottom is row = 0
 */
template<int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T>::insert_bottom(T value, int col) {
#pragma HLS inline
//    assert(col >= 0 && col < COLS);
    val[0][col] = value;
}

/* Line buffer insert top
 * Inserts a new value in the top row of the line buffer at column = col
 * The top is row = ROWS - 1
 */
template <int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T>::insert_top(T value, int col) {
#pragma HLS inline
//    assert(col >= 0 && col < COLS);
    val[ROWS-1][col] = value;
}

/* Line buffer getval
 * Returns the data value in the line buffer at position row, col
 */
template <int ROWS, int COLS, typename T> T& HT_LineBuffer<ROWS, COLS, T>::getval(int row, int col) {
#pragma HLS inline
//    assert(row >= 0 && row < ROWS && col >= 0 && col < COLS);
    return val[row][col];
}

/* Line buffer getval
 * Returns the data value in the line buffer at position row, col
 */
template<int ROWS, int COLS, typename T> T& HT_LineBuffer<ROWS, COLS, T>::operator ()(int row, int col) {
#pragma HLS inline
    return getval(row, col);
}

/* Template class of Line Buffer (array reshaped) */
template<int ROWS, int COLS, typename T>
class HT_LineBuffer<ROWS, COLS, T, 1> {
public:
	HT_LineBuffer() {
#pragma HLS array_reshape variable=val dim=1
#pragma HLS dependence variable=val inter false
#pragma HLS dependence variable=val intra false
    };
    void shift_up(int col);
    void shift_down(int col);
    void insert_bottom(T value, int col);
    void insert_top(T value, int col);
    T& getval(int row, int col);
    T& operator ()(int row, int col);

    T val[ROWS][COLS];
};

/* Member functions of LineBuffer_reshape class */

/*     +---+---+-... ...-+---+---+
 * R-1 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+  
 * R-2 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+
 *       ...     ... ...   ...
 *     +---+---+-... ...-+---+---+
 *   1 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+  
 *   0 |   |   |         |   |   |
 *     +---+---+-... ...-+---+---+
 *       0   1   ... ...  C-2 C-1   (origin is at bottom-left point)
 */

/* Member functions of LineBuffer_reshape class */

/* Line buffer shift down
 * Assumes new data pixel will be entered at the bottom of the line buffer
 * The bottom is row = 0
 */
template<int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T, 1>::shift_down(int col) {
#pragma HLS inline 
//    assert(col >= 0 && col < COLS);
    int i;
    for(i = ROWS-1; i > 0; i--) {
#pragma HLS unroll
        val[i][col] = val[i-1][col];
    }
}

/* Line buffer shift up
 * Assumes new data pixel will be entered at the top of the line buffer
 * The top is row = ROWS-1
 */
template<int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T, 1>::shift_up(int col) {
#pragma HLS inline
//    assert(col >= 0 && col < COLS);
    int i;
    for(i = 0; i < ROWS-1; i++) {
#pragma HLS unroll
        val[i][col] = val[i+1][col];
    }
}

/* Line buffer insert bottom
 * Inserts a new value in the bottom row of the line buffer at column = col
 * The bottom is row = 0
 */
template<int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T, 1>::insert_bottom(T value, int col) {
#pragma HLS inline
//    assert(col >= 0 && col < COLS);
    val[0][col] = value;
}

/* Line buffer insert top
 * Inserts a new value in the top row of the line buffer at column = col
 * The top is row = ROWS - 1
 */
template <int ROWS, int COLS, typename T> void HT_LineBuffer<ROWS, COLS, T, 1>::insert_top(T value, int col) {
#pragma HLS inline
//    assert(col >= 0 && col < COLS);
    val[ROWS-1][col] = value;
}

/* Line buffer getval
 * Returns the data value in the line buffer at position row, col
 */
template <int ROWS, int COLS, typename T> T& HT_LineBuffer<ROWS, COLS, T, 1>::getval(int row, int col) {
#pragma HLS inline
//    assert(row >= 0 && row < ROWS && col >= 0 && col < COLS);
    return val[row][col];
}

/* Line buffer getval
 * Returns the data value in the line buffer at position row, col
 */
template<int ROWS, int COLS, typename T> T& HT_LineBuffer<ROWS, COLS, T, 1>::operator ()(int row, int col) {
#pragma HLS inline
    return getval(row, col);
}

//*****************************************************************************
/* Template class of HT_window_with_linebuffer */
// ROWS     : number of rows in a window
// COLS     : number of cols in a window
// MAX_COLS : maximum number of cols in a row
// T        : data type of a window

template<int ROWS, int COLS, int MAX_COLS, typename T>
class HT_window_with_linebuffer {
public:
	HT_window_with_linebuffer() { };
    void set_size(int xval);				// set actual line width
    void insert(T val);						// insert a new val into window
    T getval(int row, int col);				// get a value in window
    HT_LineBuffer<ROWS,MAX_COLS,T,0> lb;	// ram based line buffer
    HT_Window<ROWS,COLS,T> w;				// register based window
    ap_uint<12> xsize;						// actual line width
};

template<int ROWS, int COLS, int MAX_COLS, typename T>
void HT_window_with_linebuffer<ROWS, COLS, MAX_COLS, T>::set_size(int xval )
{
	xsize = xval ;
}

template<int ROWS, int COLS, int MAX_COLS, typename T>
void HT_window_with_linebuffer<ROWS, COLS, MAX_COLS, T>::insert(T val)
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
	if(col>=xsize)
		col = 0 ;
}

template<int ROWS, int COLS, int MAX_COLS, typename T>
T HT_window_with_linebuffer<ROWS, COLS, MAX_COLS, T>::getval(int row, int col)
{
#pragma HLS inline
	return w.getval(row, col) ;
}

//*****************************************************************************
/* Template class of HT_window_with_linebuffer */
// ROWS     : number of rows in a window
// COLS     : number of cols in a window
// MAX_COLS : maximum number of cols in a row
// T        : data type of a window

template<int ROWS, int COLS, int MAX_COLS, typename T>
class HT_window_with_linebuffer_v2 {
public:
	HT_window_with_linebuffer_v2() { col = 0 ; };
    void new_row();							// window shift to next row
    void insert(T val);						// insert a new val into window
    T getval(int row, int col);				// get a value in window
    HT_LineBuffer<ROWS,MAX_COLS,T,0> lb;	// ram based line buffer
    HT_Window<ROWS,COLS,T> w;				// register based window
    ap_uint<12> col;						// current column
};

template<int ROWS, int COLS, int MAX_COLS, typename T>
void HT_window_with_linebuffer_v2<ROWS, COLS, MAX_COLS, T>::insert(T val)
{
#pragma HLS inline
	T tmp ;
	int i ;
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
}

template<int ROWS, int COLS, int MAX_COLS, typename T>
void HT_window_with_linebuffer_v2<ROWS, COLS, MAX_COLS, T>::new_row()
{
#pragma HLS inline
	col = 0;
}

template<int ROWS, int COLS, int MAX_COLS, typename T>
T HT_window_with_linebuffer_v2<ROWS, COLS, MAX_COLS, T>::getval(int row, int col)
{
#pragma HLS inline
	return w.getval(row, col) ;
}
