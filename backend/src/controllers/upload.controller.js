import { uploadImage } from '../services/storage.service.js';

export const uploadSingleImage = async (req, res) => {
  try {
    console.log('File received:', req.file); // debug

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'Please upload an image',
      });
    }

    const b64 = Buffer.from(req.file.buffer).toString('base64');
    const dataURI = `data:${req.file.mimetype};base64,${b64}`;

    const result = await uploadImage(dataURI, 'rooms');

    return res.status(201).json({
      success: true,
      message: 'Image uploaded successfully',
      data: result,
    });
  } catch (error) {
    console.error('Upload Error:', error); // important
    return res.status(500).json({
      success: false,
      message: error.message || 'Upload failed',
    });
  }
};