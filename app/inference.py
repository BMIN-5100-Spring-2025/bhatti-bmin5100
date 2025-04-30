import torch
import librosa
import numpy as np
import os
import boto3
import io
import soundfile as sf
from model import get_resnet18_model

def preprocess(audio, sr=22050, n_mels=128, hop_length=512, duration=1.0, norm_range=(0, 1)):
    """
    Loads an audio file and converts it to a normalized mel-spectrogram.

    Parameters:
        audio (ndarray): Loaded in audio file.
        sr (int): Sampling rate. Default is 22050.
        n_mels (int): Number of mel bands. Default is 128.
        hop_length (int): Number of samples between frames. Default is 512.
        duration (float): Duration of audio to load in seconds. Default is 1.0.
        norm_range (tuple): Range for normalization (default is (0, 1)).

    Returns:
        torch.Tensor: Preprocessed mel-spectrogram as a tensor.
    """


    # Generate mel-spectrogram
    mel_spec = librosa.feature.melspectrogram(y=audio, sr=sr, n_mels=n_mels, hop_length=hop_length)
    mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)

    # Normalize
    mel_min, mel_max = norm_range
    mel_spec_db = (mel_spec_db - mel_spec_db.min()) / (mel_spec_db.max() - mel_spec_db.min())  # Scale to [0, 1]
    mel_spec_db = mel_spec_db * (mel_max - mel_min) + mel_min  # Scale to desired range

    # Convert to tensor and add batch/channel dimensions
    mel_tensor = torch.tensor(mel_spec_db, dtype=torch.float32).unsqueeze(0).unsqueeze(0)  # Shape: (1, 1, n_mels, time_steps)
    return mel_tensor

def predict_audio(model, audio, class_names, device, sr=22050, n_mels=128, hop_length=512, duration=1.0):
    """
    Performs inference on a single audio sample.

    Parameters:
        model (nn.Module): Trained model.
        audio_path (str): Path to the audio file.
        class_names (list): List of class names corresponding to output indices.
        device (torch.device): Device for inference (CPU/GPU).
        sr (int): Sampling rate. Default is 22050.
        n_mels (int): Number of mel bands. Default is 128.
        hop_length (int): Number of samples between frames. Default is 512.
        duration (float): Duration of audio to load in seconds. Default is 1.0.

    Returns:
        str: Predicted class name.
        dict: Probabilities for all classes.
    """

    # Load and preprocess audio
    mel_tensor = preprocess(audio, sr=sr, n_mels=n_mels, hop_length=hop_length, duration=duration)
    mel_tensor = mel_tensor.to(device)

    # Set model to evaluation mode
    model.eval()

    # Perform inference
    with torch.no_grad():
        outputs = model(mel_tensor)  # Raw logits
        probs = torch.softmax(outputs, dim=1).squeeze(0)  # Probabilities

    # Get predicted class
    predicted_class_idx = torch.argmax(probs).item()
    predicted_class_name = class_names[predicted_class_idx]

    # Map probabilities to class names
    probabilities = {class_names[i]: probs[i].item() for i in range(len(class_names))}

    return predicted_class_name, probabilities

def reduce_noise_and_extract_cough(y, sr, noise_reduction_level=1.5):
    """
    Remove background noise and extract a 1-second segment of a cough.

    Parameters:
    - y (ndarray): Loaded in audio file
    - sr (int): Sampling rate. 
    - noise_reduction_level (float): Scale factor for noise reduction, 
      higher values result in stronger noise reduction.
    """
    
    # Estimate noise power using a small segment (e.g., first 0.5 seconds)
    noise_sample = y[:int(0.5 * sr)]
    noise_power = np.mean(np.abs(librosa.stft(noise_sample))**2, axis=1)

    # Perform Short-Time Fourier Transform (STFT) on the audio
    stft = librosa.stft(y)
    magnitude, phase = np.abs(stft), np.angle(stft)
    
    # Create a noise threshold (spectral gating)
    noise_threshold = noise_reduction_level * noise_power[:, np.newaxis]
    
    # Suppress noise below the threshold
    magnitude_denoised = np.maximum(magnitude - noise_threshold, 0)
    
    # Reconstruct the denoised audio using inverse STFT
    stft_denoised = magnitude_denoised * np.exp(1j * phase)
    y_denoised = librosa.istft(stft_denoised)
    
    # Detect cough using amplitude threshold
    amplitude_threshold = 0.05  # Adjust this based on the audio
    cough_indices = np.where(np.abs(y_denoised) > amplitude_threshold)[0]

    if len(cough_indices) == 0:
        raise ValueError("No cough detected in the audio.")
    
    # Extract a 1-second segment around the cough
    start_idx = max(0, cough_indices[0] - sr // 2)  # Start 0.5 seconds before the cough
    end_idx = min(len(y_denoised), start_idx + sr)  # Ensure the segment is 1 second
    cough_segment = y_denoised[start_idx:end_idx]

    return cough_segment


if __name__ == '__main__':
    input_directory = os.getenv("INPUT_DIR")
    model_filename = os.getenv("MODEL_FILENAME")
    s3_bucket = os.getenv("S3_BUCKET")
    s3_key = os.getenv("S3_KEY")
    input_mode = os.getenv("INPUT_MODE")
    input_filename = os.getenv("AUDIO_FILENAME")
    output_dir = os.getenv("OUTPUT_DIR", "/data/output")  # Default inside container if not set

    model_path = os.path.join("/app", model_filename)

    input_filename = os.getenv("AUDIO_FILENAME")
    input_file_path = os.path.join(input_directory, input_filename)
    s3 = boto3.client('s3')

    if input_mode == "s3":

        key = os.path.join(s3_key, input_filename)
        response = s3.get_object(Bucket=s3_bucket, Key=key)
        audio_bytes = response['Body'].read()
        audio_buffer = io.BytesIO(audio_bytes)
        y, sr = sf.read(audio_buffer)
    else:
        input_directory = os.getenv("INPUT_DIR")
        input_file_path = os.path.join(input_directory, input_filename)
        y, sr = librosa.load(input_file_path, sr=None)
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Input file not found at {model_path}")
    
        if not os.path.exists(input_file_path):
            raise FileNotFoundError(f"Input file not found at {input_file_path}")
    
    
    class_names = ['neither', 'viral', 'bacterial']
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

    model = get_resnet18_model(num_classes=len(class_names))
    model.load_state_dict(torch.load(model_path, map_location=device))
    model.to(device)

    if librosa.get_duration(y=y, sr=sr) > 1:
        cough = reduce_noise_and_extract_cough(y, sr)
    else:
        cough = y

    pred, probs = predict_audio(model, cough, class_names, device)

    os.makedirs(output_dir, exist_ok=True)  # Create output folder if missing

    output_path = os.path.join(output_dir, "output.txt")

    with open(output_path, "w") as f:
        f.write(f"Prediction: {pred}\n")
        f.write("Class probabilities:\n")
        for cls, prob in probs.items():
            f.write(f"  {cls}: {prob:.4f}\n")

    print(f"Prediction written to {output_path}")

    s3.upload_file(output_path, s3_bucket, "/outputs/output.txt")

    # print(f"The cough is likely {pred}")





