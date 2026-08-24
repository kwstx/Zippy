// MARK: - ScanReceiptView.swift

import SwiftUI

struct ScanReceiptView: View {
    @StateObject private var viewModel = ScanReceiptViewModel()
    @State private var showingImagePickerOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.black)
                .frame(height: 1)
            
            Spacer()
            
            if viewModel.isUploading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.black)
                    .scaleEffect(1.5)
                
                Text("Uploading...")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.top, 16)
            } else {
                Button(action: {
                    showingImagePickerOptions = true
                }) {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.black)
                        
                        Text("Scan receipt")
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                }
                .disabled(viewModel.isUploading)
            }
            
            if let referenceId = viewModel.referenceId {
                Text("Success: \(referenceId)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.top, 24)
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.red)
                    .padding(.top, 24)
            }
            
            Spacer()
            
            Divider()
                .background(Color.black)
                .frame(height: 1)
        }
        .background(Color.white.ignoresSafeArea())
        .confirmationDialog("Choose Image Source", isPresented: $showingImagePickerOptions, titleVisibility: .visible) {
            Button("Camera") {
                showingCamera = true
            }
            Button("Photo Library") {
                showingPhotoLibrary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $viewModel.selectedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            PhotoPicker(selectedImage: $viewModel.selectedImage)
        }
        .onChange(of: viewModel.selectedImage) { _ in
            Task {
                await viewModel.compressAndUpload()
            }
        }
    }
}
