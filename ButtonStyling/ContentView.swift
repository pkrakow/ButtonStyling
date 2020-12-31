//
//  ContentView.swift
//  ButtonStyling
//
//  Created by Paul Krakow on 12/30/20.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack{
            Button("Sample 1") {
                print("Tapped")
            }.buttonStyle(FilledRoundedCornerButtonStyle())
            Button("Sample 2") {
                print("Tapped")
            }.buttonStyle(FilledRoundedCornerButtonStyle(font: .body, bgColor: .red, fgColor: .yellow))
            HStack {
                Button("Delete") {
                    
                }.buttonStyle(SpecialButtonStyle(actionType: .delete))
                Spacer()
                Button("Cancel") {
                    
                }.buttonStyle(SpecialButtonStyle(actionType: .cancel, withImage: false))
                Button("OK") {
                    
                }.buttonStyle(SpecialButtonStyle(actionType: .confirm))
            }.padding()
            Button("Sample 3") {
                print("Tap that Circle")
            }.buttonStyle(RoundButtonStyle())
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
            ContentView()
        }
    }
}
