import torch.nn as nn
from torchvision import models

def get_resnet18_model(num_classes):
    """
    Returns a modified ResNet-18 model for mel-spectrograms.

    Parameters:
        num_classes (int): Number of output classes.

    Returns:
        nn.Module: Modified ResNet-18 model.
    """
    
    model = models.resnet18(pretrained=True)
    model.conv1 = nn.Conv2d(1, 64, kernel_size=3, stride=1, padding=1, bias=False)  # For 1-channel input
    model.fc = nn.Linear(model.fc.in_features, num_classes)  # Adjust the output layer
    return model