# ---------------------------------------------------------------
# Converts .keras models → .tflite (for ESP32 / Edge devices)
# ===============================================================

import tensorflow as tf
from tensorflow import keras
from pathlib import Path
import numpy as np
import joblib
import tempfile
import shutil

# ===== Paths =====
MODEL_DIR = Path("UPDATE_HERE")
OUT_DIR = MODEL_DIR

print("⚙️  TensorFlow Lite Conversion with Quantization")
print("✅ TensorFlow version:", tf.__version__)
print("=" * 60)

# Load the scaler to generate representative dataset
scaler = joblib.load(MODEL_DIR / "scaler.pkl")

def representative_dataset_gen():
    """Generate representative data for quantization."""
    # Generate 100 samples of random normalized data
    for _ in range(100):
        # Create random features in the normalized range
        data = np.random.randn(1, 35).astype(np.float32)  # 35 features: 24 statistical + 7 biomechanical + 5 temporal (V3 optimized)
        yield [data]

def convert_to_tflite(model_name: str, num_outputs: int):
    """Convert Keras model to TFLite with INT8 quantization."""
    keras_path = MODEL_DIR / f"{model_name}.keras"
    tflite_path = OUT_DIR / f"{model_name}.tflite"
    
    if not keras_path.exists():
        print(f"❌ Model not found: {keras_path}")
        return False
    
    print(f"\n🔄 Converting {model_name}...")
    
    try:
        # Load model
        model = keras.models.load_model(keras_path)
        print(f"   Model input shape: {model.input_shape}")
        print(f"   Model output shape: {model.output_shape}")
        
        # Create temporary directory for SavedModel
        temp_dir = Path("temp_savedmodel")
        temp_dir.mkdir(exist_ok=True)
        saved_model_dir = temp_dir / model_name
        
        # Save as SavedModel format (Keras 3 compatibility fix!)
        print(f"   Converting to SavedModel format...")
        model.export(str(saved_model_dir))
        
        # Create converter from SavedModel
        converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
        
        # Enable optimizations
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        
        # Set representative dataset for full integer quantization
        converter.representative_dataset = representative_dataset_gen
        
        # Ensure input/output are float32 (not quantized)
        # This is important for ESP32 - we want quantized weights but float I/O
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
            tf.lite.OpsSet.TFLITE_BUILTINS
        ]
        converter.inference_input_type = tf.float32
        converter.inference_output_type = tf.float32
        
        # Convert
        print(f"   Converting to TFLite...")
        tflite_model = converter.convert()
        
        # Save
        tflite_path.write_bytes(tflite_model)
        print(f"✅ Saved: {tflite_path} ({len(tflite_model)} bytes)")
        
        # Clean up temp directory
        shutil.rmtree(temp_dir)
        
        # Test the model
        return test_tflite_model(tflite_model, model_name, num_outputs)
        
    except Exception as e:
        print(f"❌ Conversion failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_tflite_model(tflite_model, model_name, num_outputs):
    """Test TFLite model for NaN outputs."""
    try:
        interpreter = tf.lite.Interpreter(model_content=tflite_model)
        interpreter.allocate_tensors()
        
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        
        print(f"   Input details: {input_details[0]['shape']}, {input_details[0]['dtype']}")
        print(f"   Output details: {output_details[0]['shape']}, {output_details[0]['dtype']}")
        
        # Test with random normalized input (35 features - V3 optimized)
        test_input = np.random.randn(1, 35).astype(np.float32)  # 35 features: 24 statistical + 6 biomechanical + 5 temporal
        interpreter.set_tensor(input_details[0]['index'], test_input)
        interpreter.invoke()
        
        output = interpreter.get_tensor(output_details[0]['index'])
        
        # Check for NaN
        if np.any(np.isnan(output)):
            print(f"❌ Test FAILED: Model produces NaN!")
            return False
        
        print(f"   Test output: {output[0]}")
        print(f"   Output sum: {np.sum(output[0]):.4f}")
        print(f"✅ Test PASSED: No NaN detected")
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        return False

# ===== Run Conversion =====
print("\nStarting conversion process...\n")

results = {}
results['idle_swing_model'] = convert_to_tflite('idle_swing_model', num_outputs=2)
results['stroke_type_model'] = convert_to_tflite('stroke_type_model', num_outputs=3)

# Summary
print("\n" + "="*60)
print("📊 CONVERSION SUMMARY")
print("="*60)

for model, success in results.items():
    status = "✅ SUCCESS" if success else "❌ FAILED"
    print(f"{model}: {status}")

if all(results.values()):
    print("\n🎾 All models converted successfully!")
    print("\nNext steps:")
    print("1. Run: python convert_to_header.py")
    print("2. Copy .h files to src/ folder")
    print("3. Upload to ESP32")
else:
    print("\n⚠️  Some models failed - check errors above")

print("="*60)