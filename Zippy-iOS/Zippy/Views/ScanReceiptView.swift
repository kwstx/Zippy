// MARK: - ScanReceiptView.swift

import SwiftUI

struct ScanReceiptView: View {
    @StateObject private var viewModel = ScanReceiptViewModel()
    @State private var showingImagePickerOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingResult = false
    @State private var showingHistory = false
    @State private var showingGroups = false

    var body: some View {
        NavigationStack {
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
                    
                } else if viewModel.isExtracting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                        .scaleEffect(1.5)
                    
                    Text("Extracting receipt...")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.top, 16)
                    
                } else if viewModel.referenceId != nil && viewModel.extractedReceipt == nil {
                    // Upload succeeded — show extract button
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.black)
                        
                        Text("Receipt uploaded")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.black)
                        
                        Button(action: {
                            Task { await viewModel.extractReceipt() }
                        }) {
                            Text("Extract items")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.black)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                } else {
                    // Default state — scan button
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
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.red)
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
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
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showingGroups) {
                GroupListView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingGroups = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 13, design: .monospaced))
                            Text("Groups")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.black)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingHistory = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13, design: .monospaced))
                            Text("History")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.black)
                    }
                }
            }
            .onChange(of: viewModel.selectedImage) { _ in
                Task {
                    await viewModel.compressAndUpload()
                }
            }
            .onChange(of: viewModel.extractedReceipt) { receipt in
                if receipt != nil {
                    showingResult = true
                }
            }
            .navigationDestination(isPresented: $showingResult) {
                if let receipt = viewModel.extractedReceipt {
                    ReceiptResultView(receipt: receipt)
                        .navigationBarBackButtonHidden(false)
                }
            }
        }
    }
}
