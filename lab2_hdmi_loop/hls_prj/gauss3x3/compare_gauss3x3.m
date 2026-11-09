% Compare a grayscale image with the output of the HLS 3x3 Gaussian kernel.
% The HLS design uses 8-bit pixels, zero padding, and truncates on conversion
% from its fixed-point accumulator to ap_uint<8>.

[fileName, folderName] = uigetfile( ...
    {'*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff', 'Image files'}, ...
    'Select an image to filter');

if isequal(fileName, 0)
    disp('No image selected.');
    return;
end

inputPath = fullfile(folderName, fileName);
inputImage = imread(inputPath);

if ~isa(inputImage, 'uint8')
    error('The HLS kernel expects an 8-bit image. Convert the input to uint8 first.');
end

if ndims(inputImage) == 3
    if size(inputImage, 3) < 3
        error('The selected image must be grayscale or RGB.');
    end
    rgb = double(inputImage(:, :, 1:3));
    grayImage = uint8(0.2989 * rgb(:, :, 1) + ...
                      0.5870 * rgb(:, :, 2) + ...
                      0.1140 * rgb(:, :, 3));
elseif ismatrix(inputImage)
    grayImage = inputImage;
else
    error('The selected image must be a 2-D grayscale or RGB image.');
end

gaussianKernel = [1 2 1; 2 4 2; 1 2 1] / 16;
filteredValues = conv2(double(grayImage), gaussianKernel, 'same');
filteredValues = min(max(floor(filteredValues), 0), 255);
filteredImage = uint8(filteredValues);

absoluteDifference = abs(double(grayImage) - double(filteredImage));

figure('Name', '3x3 Gaussian filter comparison', 'Color', 'w');
subplot(1, 3, 1);
imagesc(grayImage, [0 255]);
colormap gray;
axis image off;
title('Original grayscale');

subplot(1, 3, 2);
imagesc(filteredImage, [0 255]);
axis image off;
title('HLS 3x3 Gaussian');

subplot(1, 3, 3);
imagesc(absoluteDifference);
axis image off;
colorbar;
title('Absolute difference');

[~, baseName, ~] = fileparts(fileName);
outputPath = fullfile(folderName, [baseName '_gauss3x3.png']);
imwrite(filteredImage, outputPath);
fprintf('Filtered image saved to: %s\n', outputPath);