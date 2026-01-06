import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/core/utils/color_utils.dart';

import 'package:chess_python/core/utils/string_utils.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(profilePageStr),
        centerTitle: true,
        backgroundColor: foregroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CircleAvatar(
              child: Center(
                child: Image.asset(
                  "assets/images/profileImg.png",
                  height: 600,
                  width: 600,
                ),
              ),
            ),
            Spacer(),
            CustomElevatedbutton(
               onPressed:(){
                
               }, 
               child: Text(logoutStr),
              //() async {
              //  try{
              //   bool? confirmLogout= await showDialog<bool>(
              //     builder: (context)=>AlertDialog(title: Text(confirmLogoutStr),
              //     content: Text(reConfirmLogoutStr),
              //     actions: [
              //       TextButton(onPressed: (){
              //         Navigator.pop(context,false);
              //       }, child: Text(noStr)),
              //       TextButton(onPressed: (){
              //           Navigator.pop(context,true);
              //       }, child: Text(yesStr)),
              //     ],
              //     ), context: context);
              //    if(confirmLogout==true){
              //     await authServices.logout();
              //     await SecureStorage().clear();

              //   RouteGenerator.navigateToPage(context, Routes.loginRoute);
              //   DisplaySnackbar.show(context, logoutSuccessfulStr);
              //    }
              //  }catch(e){
              //   DisplaySnackbar.show(context, e.toString());
              //  }
              // },
              
            ),
          ],
        ),
      ),
    );
  }
}