// import 'package:chess_game_manika/models/user_model.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/widgets.dart';

// class UserTitle  extends StatelessWidget{
//   // final UserModel user;
//   final VoidCallback onAudioCall;
//   final VoidCallback onVedioCall;
//   final VoidCallback onChessInvite;

//   const UserTitle({
//     required this.user,
//     required this.onAudioCall,
//     required this.onVedioCall,
//     required this.onChessInvite,
//   });
  
//   @override
//   Widget build(BuildContext context) {
//     return ListTile(
//       leading: CircleAvatar(
//         child: Icon(Icons.person),
//       ),
//       title: Text(user.username),
//       trailing: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           IconButton(onPressed: onAudioCall, icon: Icon(Icons.call),color: Colors.green,),
//           IconButton(onPressed: onVedioCall, icon: Icon(Icons.videocam),color: Colors.blue,),
//           IconButton(onPressed: onChessInvite, icon: Icon(Icons.videogame_asset),color: Colors.amber,),
//         ],
//       ),
//     );
//   }
  
// }