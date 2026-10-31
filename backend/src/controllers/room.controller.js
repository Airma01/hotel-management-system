// Example: room.controller.js
import { uploadImage } from '../services/storage.service.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { apiResponse } from '../utils/apiResponse.js';

export const uploadRoomImage = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new AppError('No image provided', 400);
  }

  // Convert buffer to base64 data URI for Cloudinary
  const b64 = Buffer.from(req.file.buffer).toString('base64');
  const dataURI = `data:${req.file.mimetype};base64,${b64}`;

  const result = await uploadImage(dataURI, 'rooms');

  // Now you can save result.url and result.public_id into your database
  return apiResponse(res, 201, 'Image uploaded successfully', result);
});