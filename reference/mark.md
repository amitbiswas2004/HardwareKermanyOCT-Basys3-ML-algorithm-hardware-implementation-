```text
├── cnn_top.sv                 # Main CNN datapath. 
├── CNN core blocks/
│   ├── window_buffer.sv       # Produces the 3×3 sliding input window
│   ├── conv2d_3x3.sv          # Performs the actual convolution output computation
│   ├── relu_activation.sv     # ReLU after convolution
│   ├── maxpool_2x2.sv         # Max pooling after each layer
│   ├── feature_ram.sv         # Stores intermediate feature data
│   └── rom_weights.sv         # Loads weight tables from memory files
├── Dense classifier/
│   └── dense_classifier.sv    # Final fully connected classifier. 
└── Control / test/
    ├── controller_fsm.sv      # FSM for busy and result_valid handshake
    └── cnn_accuracy_tb.sv     # Testbench that instantiates cnn_top.sv.


```