module.exports = {
  formatHexUint32: function (str) {
    while (str.length < 64) { 
        str = "0" + str;
    }  
    return str;
  },
  remove0x: function (str) {
    return str.substring(2);
  }
};
