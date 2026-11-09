package cnn_params_pkg;
    localparam integer IMAGE_WIDTH       = 128;
    localparam integer IMAGE_HEIGHT      = 128;
    localparam integer IMAGE_PIXELS      = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer FEATURE_MAP_DEPTH = 63504; // 63 x 63 x 16
    localparam integer DENSE_FEATURES    = 2304;  // 6 x 6 x 64
    localparam integer NUM_CLASSES       = 4;

    // Widths are proven against the exact fixed coefficient files in memory/.
    localparam integer CONV_ACC_WIDTH    = 24;
    localparam integer DENSE_ACC_WIDTH   = 25;
    localparam integer Q_MULT_WIDTH      = 18;

    // Preserve the original rtl_ok SystemVerilog behavior.
    localparam integer CONV_ZERO_POINT   = 0;
    localparam integer DENSE_ZERO_POINT  = 86;
endpackage
