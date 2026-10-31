import cloudinary from '../../Config/cloudinary.js';
import { AppError } from '../utils/AppError.js';

/**
 * Upload a single image to Cloudinary
 * @param {Buffer|string} file - File buffer or path
 * @param {string} folder - Folder name in Cloudinary (e.g. "rooms", "hotel")
 * @returns {Promise<object>}
 */
export const uploadImage = async (file, folder = 'hotel') => {
  try {
    const result = await cloudinary.uploader.upload(file, {
      folder: `hotel-management/${folder}`,
      resource_type: 'image',
      transformation: [
        { width: 1200, height: 800, crop: 'limit' }, // resize large images
        { quality: 'auto' },
        { fetch_format: 'auto' },
      ],
    });

    return {
      public_id: result.public_id,
      url: result.secure_url,
      width: result.width,
      height: result.height,
      format: result.format,
    };
  } catch (error) {
    throw new AppError(`Image upload failed: ${error.message}`, 500);
  }
};

/**
 * Upload multiple images
 */
export const uploadMultipleImages = async (files, folder = 'hotel') => {
  const uploadPromises = files.map((file) => uploadImage(file, folder));
  return Promise.all(uploadPromises);
};

/**
 * Delete an image from Cloudinary
 * @param {string} publicId
 */
export const deleteImage = async (publicId) => {
  try {
    const result = await cloudinary.uploader.destroy(publicId);
    return result;
  } catch (error) {
    throw new AppError(`Failed to delete image: ${error.message}`, 500);
  }
};

/**
 * Delete multiple images
 */
export const deleteMultipleImages = async (publicIds) => {
  try {
    const result = await cloudinary.api.delete_resources(publicIds);
    return result;
  } catch (error) {
    throw new AppError(`Failed to delete images: ${error.message}`, 500);
  }
};