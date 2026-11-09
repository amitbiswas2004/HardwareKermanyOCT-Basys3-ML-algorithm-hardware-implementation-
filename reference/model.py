# This Python 3 environment comes with many helpful analytics libraries installed
# It is defined by the kaggle/python Docker image: https://github.com/kaggle/docker-python
# For example, here's several helpful packages to load

import numpy as np # linear algebra
import pandas as pd # data processing, CSV file I/O (e.g. pd.read_csv)

# Input data files are available in the read-only "../input/" directory
# For example, running this (by clicking run or pressing Shift+Enter) will list all files under the input directory



# You can write up to 20GB to the current directory (/kaggle/working/) that gets preserved as output when you create a version using "Save & Run All" 
# You can also write temporary files to /kaggle/temp/, but they won't be saved outside of the current session

# Use the kagglehub client library to attach Kaggle resources like competitions, datasets, and models to your session
# Learn more about kagglehub: https://github.com/Kaggle/kagglehub/blob/main/README.md

import kagglehub
# kagglehub.dataset_download('<owner>/<dataset-slug>')

import os
import shutil
import warnings
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
import torch.ao.quantization as quantization
from IPython.display import FileLink, display

# Suppress PyTorch 2.10 quantization deprecation warnings to keep the console clean
warnings.filterwarnings("ignore")

# ---------------------------------------------------------
# 1. Dataset Discovery & Loading
# ---------------------------------------------------------
def get_kermany_paths():
    base_dir = "/kaggle/input"
    for root, dirs, files in os.walk(base_dir):
        if 'train' in dirs and 'test' in dirs and 'NORMAL' in os.listdir(os.path.join(root, 'train')):
            return os.path.join(root, 'train'), os.path.join(root, 'test')
    raise FileNotFoundError("Dataset not found. Did you add 'kermany2018' to the notebook?")

train_dir, test_dir = get_kermany_paths()
print(f"Found Training Data: {train_dir}")

hw_transform = transforms.Compose([
    transforms.Grayscale(num_output_channels=1),
    transforms.Resize((128, 128)),
    transforms.ToTensor() 
])

train_data = datasets.ImageFolder(train_dir, transform=hw_transform)
train_loader = DataLoader(train_data, batch_size=128, shuffle=True, num_workers=2)

test_data = datasets.ImageFolder(test_dir, transform=hw_transform)
test_loader = DataLoader(test_data, batch_size=64, shuffle=False, num_workers=2)

# ---------------------------------------------------------
# 2. Bit-True CNN Architecture
# ---------------------------------------------------------
class HardwareOCTModel(nn.Module):
    def __init__(self):
        super(HardwareOCTModel, self).__init__()
        self.quant = quantization.QuantStub()
        self.dequant = quantization.DeQuantStub()
        
        # padding=0 prevents the C++ backend crash during INT8 conversion
        self.conv1 = nn.Conv2d(1, 16, kernel_size=3, padding=0,bias=False)
        self.relu1 = nn.ReLU()
        self.pool1 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv2 = nn.Conv2d(16, 32, kernel_size=3, padding=0,bias=False)
        self.relu2 = nn.ReLU()
        self.pool2 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv3 = nn.Conv2d(32, 64, kernel_size=3, padding=0,bias=False)
        self.relu3 = nn.ReLU()
        self.pool3 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.conv4 = nn.Conv2d(64, 64, kernel_size=3, padding=0,bias=False)
        self.relu4 = nn.ReLU()
        self.pool4 = nn.MaxPool2d(kernel_size=2, stride=2)
        
        self.flatten = nn.Flatten()
        self.fc = nn.Linear(2304, 4) 

    def forward(self, x):
        x = self.quant(x)          
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        x = self.pool3(self.relu3(self.conv3(x)))
        x = self.pool4(self.relu4(self.conv4(x)))
        x = self.flatten(x)
        x = self.fc(x)
        x = self.dequant(x)        
        return x
        
    def fuse_hardware_blocks(self):
        quantization.fuse_modules(self, [['conv1', 'relu1'],
                                         ['conv2', 'relu2'],
                                         ['conv3', 'relu3'],
                                         ['conv4', 'relu4']], inplace=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
criterion = nn.CrossEntropyLoss()

# ---------------------------------------------------------
# Phase 1: FP32 Warmup (Learning the retinal features)
# ---------------------------------------------------------
print("\n--- PHASE 1: FP32 Warmup ---")
model = HardwareOCTModel().to(device)
model.fuse_hardware_blocks()

optimizer_fp32 = optim.Adam(model.parameters(), lr=0.001)
warmup_epochs = 10

for epoch in range(warmup_epochs):
    model.train()
    running_loss = 0.0
    for i, (images, labels) in enumerate(train_loader):
        images, labels = images.to(device), labels.to(device)
        
        optimizer_fp32.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer_fp32.step()
        
        running_loss += loss.item()
        if i % 100 == 99:
            print(f"FP32 Epoch {epoch+1}, Batch {i+1}: Loss {running_loss/100:.4f}")
            running_loss = 0.0

# ---------------------------------------------------------
# Phase 2: QAT Fine-Tuning (Adapting to 8-bit constraints)
# ---------------------------------------------------------
print("\n--- PHASE 2: 8-Bit Quantization Aware Training ---")

# Revert to the default, robust per-channel FBGEMM configuration
model.qconfig = quantization.get_default_qat_qconfig('fbgemm')

# Force training mode before preparation
model.train()
quantization.prepare_qat(model, inplace=True)

# Re-initialize optimizer for the new QAT structure
optimizer_qat = optim.Adam(model.parameters(), lr=0.0001) 
qat_epochs = 5

print("Starting 5-epoch QAT loop...")
for epoch in range(qat_epochs):
    model.train()
    running_loss = 0.0
    for i, (images, labels) in enumerate(train_loader):
        images, labels = images.to(device), labels.to(device)
        
        optimizer_qat.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer_qat.step()
        
        running_loss += loss.item()
        if i % 100 == 99:
            print(f"QAT Epoch {epoch+1}, Batch {i+1}: Loss {running_loss/100:.4f}")
            running_loss = 0.0

print("\nQAT Training Complete. Ready for Step 3 (Hardware Conversion).")

# ---------------------------------------------------------
# 3. Hardware Conversion & Verification
# ---------------------------------------------------------
print("\nConverting model to true INT8...")
model.to('cpu')
model.eval()
quantization.convert(model, inplace=True)

print("Evaluating exact INT8 Hardware Accuracy on Unseen Test Data...")
correct = 0
total = 0

with torch.no_grad():
    for images, labels in test_loader:
        outputs = model(images)
        _, predicted = torch.max(outputs.data, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()

final_accuracy = 100 * correct / total
print(f"Final Hardware INT8 Accuracy: {final_accuracy:.2f}%")

# ---------------------------------------------------------
# 4. Bit-True Hardware Parameter Extraction (Per-Channel)
# ---------------------------------------------------------
import os
import shutil
import numpy as np
from IPython.display import FileLink, display

print("\n--- EXTRACTING BIT-TRUE HARDWARE MATRICES (BIAS-FREE CONV) ---")
output_dir = '/kaggle/working/bit_true_matrices'
os.makedirs(output_dir, exist_ok=True)

def write_hex_mem(filename, data_array, bit_width):
    mask = (1 << bit_width) - 1
    hex_chars = bit_width // 4
    filepath = os.path.join(output_dir, filename)
    with open(filepath, 'w') as f:
        for val in data_array.flatten():
            hex_val = f"{(int(val) & mask):0{hex_chars}X}\n"
            f.write(hex_val)

def extract_hardware_layer(layer_name, q_layer, input_scale):
    weights = q_layer.weight().int_repr().numpy()
    
    # Restore per-channel scale extraction
    weight_scales = q_layer.weight().q_per_channel_scales().numpy()
    output_scale = q_layer.scale
    output_zero_point = q_layer.zero_point

    num_channels = len(weight_scales)
    q24_multipliers = np.zeros(num_channels, dtype=np.int32)

    for i in range(num_channels):
        effective_scale = input_scale * weight_scales[i]
        m_val = (effective_scale / output_scale) * (1 << 24)
        q24_multipliers[i] = int(np.round(m_val))

    write_hex_mem(f"{layer_name}_weights.mem", weights, 8)
    write_hex_mem(f"{layer_name}_multipliers.mem", q24_multipliers, 32)
    
    print(f"{layer_name.ljust(15)} | Output Zero Point (Add in SV): {output_zero_point}")
    return output_scale 

s_in_0 = model.quant.scale.item()
print(f"ADC Input Scale : {s_in_0:.6f}\n")

s_in_1 = extract_hardware_layer("layer1", model.conv1, s_in_0)
s_in_2 = extract_hardware_layer("layer2", model.conv2, s_in_1)
s_in_3 = extract_hardware_layer("layer3", model.conv3, s_in_2)
s_in_4 = extract_hardware_layer("layer4", model.conv4, s_in_3)

# Extract final Dense layer (Retains its Bias)
dense_weights = model.fc.weight().int_repr().numpy()
dense_bias = model.fc.bias().detach().numpy()
dense_w_scale = model.fc.weight().q_per_channel_scales().numpy()[0] 
dense_out_scale = model.fc.scale

dense_eff_scale = s_in_4 * dense_w_scale
dense_int32_bias = np.round(dense_bias / dense_eff_scale).astype(np.int32)
dense_q24_mult = int(np.round((dense_eff_scale / dense_out_scale) * (1 << 24)))

write_hex_mem("layer5_dense_weights.mem", dense_weights, 8)
write_hex_mem("layer5_dense_biases.mem", dense_int32_bias, 32)
write_hex_mem("layer5_dense_multiplier.mem", np.array([dense_q24_mult]), 32)

print(f"layer5_dense    | Output Zero Point (Add in SV): {model.fc.zero_point}")

print("\nZipping files for download...")
shutil.make_archive('/kaggle/working/bit_true_hw_files', 'zip', output_dir)
display(FileLink('bit_true_hw_files.zip'))

import os
import shutil
import torch
import collections
from IPython.display import FileLink, display

print("\n--- EXTRACTING BIT-TRUE TESTBENCH VECTORS ---")
tb_dir = '/kaggle/working/testbench_vectors'

if os.path.exists(tb_dir):
    shutil.rmtree(tb_dir)
os.makedirs(tb_dir, exist_ok=True)

# Safeguard: Patch missing PyTorch dictionaries caused by INT8 C++ conversion
for m in model.modules():
    for hook in ['_backward_hooks', '_backward_pre_hooks', '_forward_hooks', '_forward_pre_hooks']:
        if not hasattr(m, hook):
            setattr(m, hook, collections.OrderedDict())

classes = test_data.classes # ['CNV', 'DME', 'DRUSEN', 'NORMAL']

for class_idx, class_name in enumerate(classes):
    for img_tensor, label in test_data:
        if label == class_idx:
            img_batched = img_tensor.unsqueeze(0)
            
            # 1. Extract Bit-True Hardware Pixels
            quantized_img = model.quant(img_batched)
            hw_pixels = quantized_img.int_repr().numpy().flatten()
            
            # 2. Get Ground Truth from the Hardware Model
            with torch.no_grad():
                hw_out = model(img_batched)
                _, predicted = torch.max(hw_out.data, 1)
                pred_class_name = classes[predicted.item()]
            
            # 3. Write to Hex File
            filename = f"tb_img_{class_name}_expected_{pred_class_name}.mem"
            filepath = os.path.join(tb_dir, filename)
            
            with open(filepath, 'w') as f:
                for pixel in hw_pixels:
                    f.write(f"{pixel:02X}\n")
            
            print(f"Exported: {filename.ljust(35)} (16,384 pixels)")
            break 

print("\nZipping testbench vectors...")
shutil.make_archive('/kaggle/working/testbench_vectors', 'zip', tb_dir)
display(FileLink('testbench_vectors.zip'))