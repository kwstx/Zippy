// MARK: - ScanReceiptView.swift

import SwiftUI

struct ScanReceiptView: View {
    @StateObject private var viewModel = ScanReceiptViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingImagePickerOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingResult = false
    @State private var showingHistory = false
    @State private var showingGroups = false
    @State private var showingManualEntry = false
    @State private var showingPaywall = false
    @State private var showingPrivacy = false

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
                    // Default state — scan or manual entry options
                    VStack(spacing: 28) {
                        Button(action: {
                            showingImagePickerOptions = true
                        }) {
                            VStack(spacing: 14) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 72))
                                    .foregroundColor(.black)
                                
                                Text("Scan receipt")
                                    .font(.system(.title2, design: .rounded))
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                        }
                        .disabled(viewModel.isUploading)

                        HStack {
                            Rectangle().fill(Color(white: 0.8)).frame(height: 1)
                            Text("OR")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))
                                .padding(.horizontal, 8)
                            Rectangle().fill(Color(white: 0.8)).frame(height: 1)
                        }
                        .padding(.horizontal, 60)

                        Button(action: {
                            showingManualEntry = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 13, design: .monospaced))
                                Text("Manual entry / AI correction form")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        }
                    }
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
            .sheet(isPresented: $showingPaywall) {
                PaywallSheetView(subscriptionManager: subscriptionManager)
            }
            .sheet(isPresented: $subscriptionManager.showPaywall) {
                PaywallSheetView(subscriptionManager: subscriptionManager)
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacySettingsView()
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
                ToolbarItem(placement: .principal) {
                    Button(action: { showingPaywall = true }) {
                        Text(subscriptionManager.isPro ? "PRO" : "FREE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(subscriptionManager.isPro ? .white : .black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(subscriptionManager.isPro ? Color.black : Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 0.8))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showingHistory = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, design: .monospaced))
                                Text("History")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(.black)
                        }

                        Button(action: { showingPrivacy = true }) {
                            Image(systemName: "shield")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.black)
                        }
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
            .navigationDestination(isPresented: $showingManualEntry) {
                EditableReceiptFormView()
            }   }
        }
    }
}
